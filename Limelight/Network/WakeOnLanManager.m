//
//  WakeOnLanManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/2/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//
//  Artemis: the magic packet goes straight to every address the PC is known by (unicast) as
//  well as to the broadcast addresses, a few times over. Since iOS 14.5 an app may only send
//  broadcasts with the com.apple.developer.networking.multicast entitlement (Artemis doesn't
//  have it yet: README, "Waking a PC"), and without it sendto() to a broadcast address fails.
//  A unicast magic packet still reaches a sleeping PC whose network adapter answers ARP for it
//  (Windows' ARP offload) or whose address this iPhone still has in its neighbour cache: the
//  adapter wakes on the magic pattern whatever the packet's destination address.
//

#import "WakeOnLanManager.h"
#import "Utils.h"
#import <CoreFoundation/CoreFoundation.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <errno.h>
#import <string.h>

@implementation WakeOnLanManager

static const int numStaticPorts = 3;
static const int staticPorts[numStaticPorts] = {
    9, // Standard WOL port (discard; privileged port)
    7, // Echo: the other port WoL tools use
    47009, // Port opened by Moonlight Internet Hosting Tool for WoL (non-privileged port)
};
static const int numDynamicPorts = 5;
static const int dynamicPorts[numDynamicPorts] = {
    47998, 47999, 48000, 48002, 48010, // Ports opened by GFE/Sunshine
};
/// Each target gets the packet this many times, this far apart: a sleeping PC's adapter can
/// miss the first while the switch or the ARP answer catches up.
static const int numRounds = 3;
static const useconds_t roundGapMicroseconds = 400000;

+ (void) populateAddress:(struct sockaddr_storage*)addr withPort:(unsigned short)port {
    if (addr->ss_family == AF_INET) {
        struct sockaddr_in *sin = (struct sockaddr_in*)addr;
        sin->sin_port = htons(port);
    }
    else if (addr->ss_family == AF_INET6) {
        struct sockaddr_in6 *sin6 = (struct sockaddr_in6*)addr;
        sin6->sin6_port = htons(port);
    }
}

/// The PC's addresses, each once, with the port its HTTP server is on there.
+ (NSArray<NSArray*>*) unicastTargetsOfHost:(TemporaryHost*)host {
    NSMutableArray<NSArray*>* targets = [NSMutableArray array];
    NSMutableSet<NSString*>* seen = [NSMutableSet set];
    NSArray* candidates = @[host.localAddress ?: @"", host.activeAddress ?: @"", host.address ?: @"",
                            host.externalAddress ?: @"", host.ipv6Address ?: @""];
    for (NSString* addressPort in candidates) {
        if (addressPort.length == 0) {
            continue;
        }
        NSString* rawAddress = [Utils addressPortStringToAddress:addressPort];
        if (rawAddress.length == 0 || [seen containsObject:rawAddress]) {
            continue;
        }
        [seen addObject:rawAddress];
        [targets addObject:@[rawAddress, @([Utils addressPortStringToPort:addressPort])]];
    }
    return targets;
}

/// 255.255.255.255 and the broadcast address of each IPv4 network this device is on.
+ (NSArray<NSString*>*) broadcastAddresses {
    NSMutableOrderedSet<NSString*>* addresses = [NSMutableOrderedSet orderedSetWithObject:@"255.255.255.255"];
    struct ifaddrs* interfaces = NULL;
    if (getifaddrs(&interfaces) == 0) {
        for (struct ifaddrs* ifa = interfaces; ifa != NULL; ifa = ifa->ifa_next) {
            if (ifa->ifa_addr == NULL || ifa->ifa_addr->sa_family != AF_INET || ifa->ifa_dstaddr == NULL ||
                !(ifa->ifa_flags & IFF_UP) || !(ifa->ifa_flags & IFF_BROADCAST) || (ifa->ifa_flags & IFF_LOOPBACK)) {
                continue;
            }
            char text[INET_ADDRSTRLEN];
            if (inet_ntop(AF_INET, &((struct sockaddr_in*)ifa->ifa_dstaddr)->sin_addr, text, sizeof(text)) != NULL) {
                [addresses addObject:[NSString stringWithUTF8String:text]];
            }
        }
        freeifaddrs(interfaces);
    }
    return addresses.array;
}

/// Sends the packet to each port of one address (a name may resolve to several). Returns how
/// many sends went out; failures are described in `errors`.
+ (int) send:(NSData*)payload to:(NSString*)rawAddress ports:(NSArray<NSNumber*>*)ports
   broadcast:(BOOL)broadcast errors:(NSMutableOrderedSet<NSString*>*)errors {
    struct addrinfo hints, *res, *curr;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    hints.ai_flags = AI_ADDRCONFIG;
    int err = getaddrinfo([rawAddress UTF8String], NULL, &hints, &res);
    if (err != 0 || res == NULL) {
        [errors addObject:[NSString stringWithFormat:@"%@: can't resolve (%s)", rawAddress, gai_strerror(err)]];
        return 0;
    }

    int sent = 0;
    // Try all addresses that this DNS name resolves to. We have to create a new socket each
    // time because the addresses may be different address families.
    for (curr = res; curr != NULL; curr = curr->ai_next) {
        int wolSocket = socket(curr->ai_family, SOCK_DGRAM, IPPROTO_UDP);
        if (wolSocket < 0) {
            [errors addObject:[NSString stringWithFormat:@"%@: no socket (%s)", rawAddress, strerror(errno)]];
            continue;
        }
        if (broadcast) {
            int val = 1;
            setsockopt(wolSocket, SOL_SOCKET, SO_BROADCAST, &val, sizeof(val));
        }

        struct sockaddr_storage addr;
        memset(&addr, 0, sizeof(addr));
        memcpy(&addr, curr->ai_addr, curr->ai_addrlen);
        for (NSNumber* port in ports) {
            [WakeOnLanManager populateAddress:&addr withPort:port.unsignedShortValue];
            long result = sendto(wolSocket, [payload bytes], [payload length], 0, (struct sockaddr*)&addr, curr->ai_addrlen);
            if (result == (long)[payload length]) {
                sent++;
            }
            else {
                int code = errno;
                NSString* note = @"";
                if (broadcast && (code == EHOSTUNREACH || code == EPERM || code == EACCES || code == ENETUNREACH)) {
                    note = @" - iOS blocks broadcasts without the com.apple.developer.networking.multicast entitlement";
                }
                [errors addObject:[NSString stringWithFormat:@"%@: %s (errno %d)%@", rawAddress, strerror(code), code, note]];
            }
        }
        close(wolSocket);
    }
    freeaddrinfo(res);
    return sent;
}

+ (void) wakeHost:(TemporaryHost*)host {
    NSData* wolPayload = [WakeOnLanManager createPayload:host];
    if (wolPayload.length != 102) {
        Log(LOG_E, @"Wake-on-LAN: %@ has no usable MAC address (%@)", host.name, host.mac);
        return;
    }

    NSArray<NSArray*>* unicastTargets = [self unicastTargetsOfHost:host];
    NSArray<NSString*>* broadcastTargets = [self broadcastAddresses];
    NSMutableArray<NSNumber*>* broadcastPorts = [NSMutableArray array];
    for (int j = 0; j < numStaticPorts; j++) {
        [broadcastPorts addObject:@(staticPorts[j])];
    }

    int unicastSent = 0, broadcastSent = 0;
    NSMutableOrderedSet<NSString*>* unicastErrors = [NSMutableOrderedSet orderedSet];
    NSMutableOrderedSet<NSString*>* broadcastErrors = [NSMutableOrderedSet orderedSet];
    for (int round = 0; round < numRounds; round++) {
        if (round > 0) {
            usleep(roundGapMicroseconds);
        }
        for (NSArray* target in unicastTargets) {
            NSMutableArray<NSNumber*>* ports = [broadcastPorts mutableCopy];
            unsigned short basePort = [target[1] unsignedShortValue];
            for (int j = 0; j < numDynamicPorts; j++) {
                // Offset the WoL dynamic ports by the base port
                [ports addObject:@((unsigned short)(((int)dynamicPorts[j] - 47989) + basePort))];
            }
            unicastSent += [self send:wolPayload to:target[0] ports:ports broadcast:NO errors:unicastErrors];
        }
        for (NSString* address in broadcastTargets) {
            broadcastSent += [self send:wolPayload to:address ports:broadcastPorts broadcast:YES errors:broadcastErrors];
        }
    }

    NSMutableArray<NSString*>* unicastNames = [NSMutableArray array];
    for (NSArray* target in unicastTargets) {
        [unicastNames addObject:target[0]];
    }
    Log(LOG_I, @"Wake-on-LAN for %@ (%@), %d rounds: %d unicast packets sent to %@; %d broadcast packets sent to %@",
        host.name, host.mac, numRounds, unicastSent, unicastNames.count > 0 ? [unicastNames componentsJoinedByString:@", "] : @"no address",
        broadcastSent, [broadcastTargets componentsJoinedByString:@", "]);
    for (NSString* error in unicastErrors) {
        Log(LOG_W, @"Wake-on-LAN unicast failed: %@", error);
    }
    for (NSString* error in broadcastErrors) {
        Log(LOG_W, @"Wake-on-LAN broadcast failed: %@", error);
    }
}

+ (NSData*) createPayload:(TemporaryHost*)host {
    NSMutableData* payload = [[NSMutableData alloc] initWithCapacity:102];

    // 6 bytes of FF
    UInt8 header = 0xFF;
    for (int i = 0; i < 6; i++) {
        [payload appendBytes:&header length:1];
    }

    // 16 repitiions of MAC address
    NSData* macAddress = [self macStringToBytes:host.mac];
    if (macAddress.length != 6) {
        return [NSData data];
    }
    for (int j = 0; j < 16; j++) {
        [payload appendData:macAddress];
    }

    return payload;
}

+ (NSData*) macStringToBytes:(NSString*)mac {
    NSString* macString = [[mac stringByReplacingOccurrencesOfString:@":" withString:@""] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    Log(LOG_D, @"MAC: %@", macString);
    if (macString.length != 12) {
        return [NSData data];
    }
    return [Utils hexToBytes:macString];
}

@end
