---
layout: post
title: "Publishing my first Rust crate"
date: 2025-5-7 15:00:00
tags: [rust, open-source, programming]
excerpt: "For years I've been wondering how I can contribute to open source in Rust. Today, I
completed a first milestone by publishing my first Rust crate."
---

A few years ago I had expressed the wish to "be involved in shaping Rust's future by making 
contributions to its software while keeping learning its concepts and intricacies" in one of my
[blog posts](https://n-eq.github.io/blog/2022/11/01/rust-fiddling-2-years).

In retrospect, I tend to consider that goal as very ambitious. However, I am happy to say that I have today 
made one very small step towards that goal by publishing a Rust crate (`pcd8544-hal`) on [crates.io](https://crates.io/crates/pcd8544-hal/).
The crate is a driver library based on `embedded-hal` for the PCD8544 LCD controller, which is commonly found in
small LCD displays (Nokia's 5110, for example). 

## The journey

Creating this crate wasn't a goal in itself. I had some spare time and old hardware parts lying around on my desk.
I thought it would be a good entrypoint to dive into embedded Rust and learn more about its ecosystem.
As it turned out, working on AVR microcontrollers is quite straightforward, especially for classic boards
like the Arduino Uno, which I picked up to quickly learn and test the code.

Some folks (not too many) had already worked on Rust drivers for the PCD8544 controller. The version I chose to
use was [dancek](https://github.com/dancek/pcd8544-hal)'s. It worked well, and I was able to get the display up and running
after a few attemps to get the wiring right. Although being functional, the code was a bit obsolete (e.g.: still on Rust 2015),
and not very well documented.
I decided to fork the repository and start working on it. I wanted to make it more idiomatic, give it a bit of freshing up,
add some documentation, and make some improvements.
The author kindly agreed that I fork the repository and publish my own version of the driver, since he was not actively maintaining it anymore,
and wasn't planning to put together the hardware for it anytime soon.

## Design choices

Although I didn't start from scratch, I had to make some design choices, and to spend some time going back and forth
between the datasheet and the code to understand how things worked, especially writing ASCII characters to the screen, and
making sure every sent command made sense.
This led me to make some minor improvements, but although I had listed some ideas for future developments, I decided to keep the crate as simple
as possible and focus on core features.

## Publishing the crate

However minor it may seem, publishing this crate as a first-timer was a bit of an achievement for me. Seeing the crate's page on crates.io
made its impression on me, and in the first hours after publishing, I couldn't resist the urge to check the page every now and then to see if
anyone had downloaded it.
Hitting the publish button reminded me of the time I created and published my first Vim plugin and how impatient I was to see the number of downloads
grow.

## What's next?

During the time I spent working on the crate (helped by reading existing C/C++ drivers), I had come accross some ideas for future improvements (scrolling
implementation, screen orientation, more idiomatic API, low-level code refactoring), which would take some time to implement.
These ideas are definitely something to consider for next version of the crate, that I plan to publish in the next weeks.
