---
layout: post
title: "Write-up: Zephyr Project's meteoric rise"
date: 2025-05-28
tags: [writeup, zephyr, embedded, webinar]
excerpt: "A write-up on Memfault's webinar on \"Zephyr’s Meteoric Rise and What It Means for the Future of Embedded\""
---

The embedded systems landscape is undergoing a significant transformation. In
Memfault’s Coredump \#009 session, Kate Stewart, VP of Dependable Embedded
Systems at the Linux Foundation, joined François Baldassari and Chris Coleman
to discuss the subject.\
The webinar delved into the factors
propelling Zephyr RTOS into mainstream adoption, and what this shift could mean
for developers, embedded product teams, and the embedded ecosystem as a whole.

## Why Zephyr, why now?

At its origins, Zephyr stems from Intel's strategic move to develop an
open-source RTOS with an original value proposition: "by developers, for
developers" aiming to foster collaboration and innovation in a dedicated
embedded community. \
Nowadays, Zephyr’s ascent isn’t merely about replacing
legacy RTOSes; it represents a fundamental shift in how embedded systems are
developed. \
Kate highlighted that Zephyr's current rise mainly comes from its scalability,
security, and robust community support. Its open-source nature fosters
collaboration and accelerates innovation, making it an attractive choice for
modern embedded applications. Another important feature is Zephyr's commit
sign-off policy, which sets it apart from other open-source projects that
require contribution agreement and more bureaucratic processes.

## Regulatory pressures and the CRA

The soon-to-come EU Cyber Resilience Act (CRA) introduces new compliance
requirements for embedded systems. Kate Stewart emphasized that Zephyr’s
transparent governance and rigorous security practices position it well to meet
these challenges. However, the broader open-source community must proactively
address these regulatory demands to ensure continued innovation and compliance.

In the same vein, she emphasized Zephyr’s maturity in vulnerability management,
a topic that is too often sidestepped in embedded development. Unlike many RTOS
projects where CVE reporting is opaque or entirely absent, Zephyr has become an
example of open, traceable vulnerability disclosure. In fact (and this is
a common misconception noted by François Baldassari) the project not only
tracks CVEs diligently but also provides public, structured visibility into
security fixes and their impact, a “hard-won outcome” of years of process work.
Zephyr’s approach marks a refreshingly responsible model, setting expectations
for what security transparency can look like in open embedded software.

## Discussion about popular criticism of Zephyr

> “We’re pretty close to the level of RTOS you need.”\
> — Kate Stewart.

In response to Chris Coleman's question about Zephyr’s suitability for
big, complex, and real-time systems — often a sticking point in RTOS
selection — Kate offered a reassuring update: performance is a top priority,
and the next release is expected to deliver meaningful improvements on existing
benchmarks. _"We're pretty close to the level of RTOS you need"_, she noted,
hinted that current efforts are aimed at bring Zephyr closer to parity with
traditional RTOSes. \
This suggests that Zephyr isn’t just maturing in breadth (tooling, security,
ecosystem), it’s also leveling up and becoming a stronger candidate even for
demanding real-time applications.

## Some takeaways

For embedded engineers, RTOSes like Zephyr are no longer fringe options but serious
contenders for production systems. With upcoming regulatory requirements such
as the CRA, choosing a project that prioritizes security, governance, and
long-term maintainability is a strategic necessity, not just
a technical preference.

Tech and product teams should consider Zephyr’s growing strengths: a solid
community, active security management, regulatory readiness, and a roadmap
focused on closing the performance gap. Whether you’re replacing a legacy RTOS
or starting fresh, Zephyr’s trajectory makes
a strong case for placing it on your shortlist.

## See also

- The recording of the webinar on [YouTube](https://www.youtube.com/watch?v=AHZ6lpETQ00).
