//
//  DiscoveryWorker.h
//  Moonlight
//
//  Created by Diego Waxemberg on 1/2/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "TemporaryHost.h"
#import "ServerInfoResponse.h"

@interface DiscoveryWorker : NSOperation

- (id) initWithHost:(TemporaryHost*)host uniqueId:(NSString*)uniqueId;
- (void) discoverHost;
- (TemporaryHost*) getHost;

/// One serverinfo answer from one of the host's addresses, as a poll judges it: whether it
/// speaks for this host (then the host is updated from it), or counts as no answer.
/// A PC this client paired with (its certificate is pinned) counts only when it answers over
/// HTTPS with that certificate: a plain HTTP answer says "not paired" and hides the MAC
/// address whatever the truth, so it would turn a PC that is going to sleep, waking up or
/// briefly refusing into "Not paired" and lose its Wake-on-LAN address. Only a PC that has
/// refused this client in every poll for `refusalGrace` seconds is believed (it really was
/// unpaired, or Apollo was reinstalled with a new certificate), so it can be paired again.
+ (BOOL) acceptResponse:(ServerInfoResponse*)response forHost:(TemporaryHost*)host;

/// The answer is from this PC (the right UUID), but not authenticated while its certificate is pinned.
+ (BOOL) isRefusal:(ServerInfoResponse*)response forHost:(TemporaryHost*)host;

/// The end of a poll: online when an answer was accepted. A poll with no answer at all ends a
/// run of refusals.
+ (void) finishPollOfHost:(TemporaryHost*)host answered:(BOOL)answered refused:(BOOL)refused;

/// How long a paired PC must keep refusing this client before it shows as not paired.
+ (NSTimeInterval) refusalGrace;

@end
