---
layout: post
title: "Unlocking uplink frame retries mecanism on Telecom Design's Sigfox modules"
date: 2020-04-07 22:00:00
tags: [sigfox, telecom-design, reverse-engineering]
---

When I first met Christophe Fourtet (Sigfox's Chief Scientific Officer) in June 2018,
he told me that the company has always been conservative in terms of the used
bandwidth. However at the time, they were already planning and testing uplink messages using
a single frame (in contrast with the mandatory triple-redundancy mecanism initially adopted
by the network for QoS matters.) A few months later, Sigfox open-sourced its radio specifications
(on device side). In the document (at least the November 2019 version, I couldn't
retrieve February's release), it is officially stated that endpoints can
choose to send single vs multiple (read 3) frames in an uplink message (cf. section
[3.13.1 Single/multiple frame principle](https://web.archive.org/web/20200521024316/https://storage.sbg.cloud.ovh.net/v1/AUTH_669d7dfced0b44518cb186841d7cbd75/prod_medias/build/40599z1k361d4ht/Sigfox%20radio%20specifications%20v1.4%20%20November%202019.pdf#page=18)).

What this meant was that all Sigfox device manufacturers would subsequently
update their libraries to allow makers to choose the most suitable procedure
with regard to their applications. The main benefit from sending a single-frame
message instead of a triple-frame one is reducing the resulting energy
consumption as we'll see later in this article.
However, for reasons I ignore, Telecom Design's SDK did not
integrate this modification (although they released a new version after 4 years
in August 2019) and continued to enforce triple-frame messages on uplinks.
The argument `reply` in `TD_SIGFOX_SendV1` being practically useless.
Given that the RF part of the SDK is closed-source and only provided through
a compiled archive, I decided to investigate.

In this article, I'll use [Ghidra](https://ghidra-sre.org) to explore [Telecom Design's
SDK](https://github.com/Telecom-Design/TD_RF_Module_SDK), in particular the RF 
closed-source part, to show how, almost four years before, they anticipated 
this change by silently allowing this evolution.

We start by first decompiling `TD_SIGFOX_SendV1` function located in `td_sigfox.o`
object in `libtdrf.a` archive.
![]({{ "/assets/images/td_sigfox_sendv1_decompilation.png" | relative_url }} "Ghidra function decompilation")

Without going any further, we can make the following observations :

* `retry` starts at 0. As a result, triple-frame messages have a `retry` value
of 2, whereas in case of single-frame messages, the value is 0,
* For user uplinks, this variable is only forced to 2 in the branch lines 29 to 32 above:

```c
if (!ack) {
    if (mode == 3) {
        // MODE_OOB_ACK
        retry = 0;
    } else {
        // MODE_BIT, MODE_FRAME, MODE_OOB
        if (!ByPassRetryTest) {
            retry = 2; // <- overwriting occurs here
        }
    }
}
```

Looking for the variable `ByPassRetryTest`, we discover that it's defined in bss.
This means two things: 
1. It is left uninitialized (thus zeroized, so `false`). This is the reason why 
all calls to `TD_SIGFOX_Send` go by default through the above branch 
and therefore, from a user standpoint, the value of `retry` is useless.
2. It is declared at file-scope as it's not in the function's declared variables.

Naturally, we would next go looking for the references to this variable in
td_sigfox.o file.

Ghidra makes this task very easy. It yields two operations related to
this variable, the first one is a read operation (in `TD_SIGFOX_SendV1`),
and the second is a write (bingo!). The write operation occurs in the function
`TD_SIGFOX_AllowExtendedUse` decompiled below.

```c
void TD_SIGFOX_AllowExtendedUse(uint32_t key)
{
    ByPassRetryTest = (_Bool) (key == 0x83828289);
    return;
}
```

Fair enough. The idea is that a simple call to the function above with
the right key (which is plain-text hardcoded but that's not a real
issue) would "unlock" the retry mecanism and allow the user to choose
the number of frames that suits his needs.

### Testing

Testing is pretty straightforward. The idea is as stated before to call
`TD_SIGFOX_AllowExtendedUse` with the right key (the previously listed
value is fake) before sending any message. After that, we are free
to choose the number of repetitions depending on the importance of the 
message or based on any other strategy.

After testing we can verify in two ways:

#### Using a scope

This method is a bit cumbersome as it requires connecting extra hardware
to measure current consumption by the device, but the result is conclusive:
we can observe how the device behaves when sending a single-frame versus
when it sends three consecutive frames. This also shows how we can divide
the current consumption by three when chosing single-frame uplinks instead
of triple-frames.
![]({{ "/assets/images/tx_frames.png" | relative_url }} "Current consumption: Single-frame vs triple-frame uplink messages")

#### Using Sigfox backend

The alternative to the previous method is directly checking the device's
message history in Sigfox backend (or through API access). This 
nevertheless requires you to have sufficient rights to be able to view 
message details (however I'm not sure which role is needed for this, 
the documentation is not really clear on this point.)

Similarly, we can easily verify for a given message the number of frames
emitted by the end product, as in the following screenshot.

![]({{ "/assets/images/tx_frames_backend.png" | relative_url }} "Single-frame vs triple-frame uplink messages")
