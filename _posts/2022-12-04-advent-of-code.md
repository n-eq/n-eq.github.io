---
layout: post
title: "Advent of Code, yet another reason to wake up early"
date: 2022-12-04 19:30:00
tags: [learning, programming-languages, development, advent-of-code]
excerpt: "Waking up early for fun and profit (climbing AoC's leaderboard)"
---

Since several weeks, I made the decision to wake up at 6am (which is earlier than I need to, except on weekends.)
Far from being influenced by some productivity guru, shaving off some sleeping time was a good
thing as it allowed me to exercise, read/write, eat a healthy breakfast and eventually start
working alone before the daily hussle of meetings and team rituals.
For someone that needs more than average sleep hours (8 hours is far from being enough for me), this was a bold move
and it turned out I couldn't keep up with this rhythm as the winter made things a bit more difficult.
It was at the same period that my work (and workout) load significantly dropped and I feeled less the need
to start my day earlier than necessary.

_What do the vicissitudes of my sleeping and wake up times have to do with this blog post?_


### Advent of Code
[Advent of Code](https://adventofcode.com/) is an advent calendar of small programming puzzles of increasing difficulty that can
be solved in any language.
Each day a new puzzle is posted at midnight EST (UTC-5) and users compete by solving the exercise in two parts.
Some of my colleagues have created a private leaderboard for fun. \
Since I live in Paris, the challenges are added daily at 6 am CET (UTC+1), the earlier I'm up after 6 the better
it is for me to solve the challenges and win as much points as possible to keep a decent position in the leaderboard.

![]({{ "/assets/images/advent-of-code-2022.png" | relative_url }})
_My company's private leaderboard (started writing this article when I was 4th, became 1st at the time of publication)_

In this article, I would like to highlight some benefits of ~~waking up early~~ taking part in the Advent of Code.

### Variating languages as a refresher
For my first year doing the Advent of Code, I chose to variate as much as possible the programming language in
which I solve the puzzles as a personal challenge.
I am often a bit hesitant when asked the question: "how many programming languages do you know?". This is a tricky question
and people tend to answer with the number of programming languages they learned or used **at some point in their career**.
I personally think it's wrong, as we humans have limited memory and it's only a matter of few weeks with no practicing
until some concepts, details, and tricks are gone. Sure, you don't need to re-learn again the language, but you'll sure
lack some automatisms at first.

For about 2 years now my main focus was on [Rust](https://n-eq.github.io/blog/2022/11/01/rust-fiddling-2-years), and I didn't have the
chance to professionally write substantial C/C++ code, for which I have a strong theoretical and practical background. I thought this
was a very adequate occasion to brush up my skills.\
The best example of this is [Day 5](https://adventofcode.com/2022/day/5) for which I had to reimplement from scratch a linked list variant
to handle moving crates around different stacks. Finishing that day's challenge was one of the most rewarding so far.

Doing the challenge in a language deeply buried in your memory is a very efficient way to review basics. This has a cost, though.
You'll lose some speed along the way and will need to sacrifice some points. If you're playing to win, this might not be the
best strategy.

In retrospect, however, I regret not having used edgy languages like Bash or Java (_sorry, Java folks_) in the beginning of the
month as the puzzles would have been much easier to solve.

### Learning a new language
I saw a few people saying they're doing the challenge to learn a new language (Rust, most of the times). I don't think that's a great
idea. Why? Unless you're considering the puzzles are plain exercises (which is questionable), you'll be fighting twice: against the puzzle
and the language (and Rust can be really painful with this regard.)\
Solving the challenges in a language you don't **master** yet, but for which you however have a good grip, can be a nice option to
speedify your learning and acquire some solid foundations on its concepts and intricacies.\
This is actually my case, as I don't consider myself a fluent Rust developer yet.
Although I haven't made use of any advanced notions (templates, generics), solving some puzzles in Rust
helped me nonetheless realize how powerful are some high-level concepts such as iterators.

### Learning from others
AoC has a really great community on [Reddit](https://www.reddit.com/r/adventofcode/). Regardless of funny memes, users also post their
solutions, especially when they think it's worthful. I often take time to sift through each day's solutions not only for the joy of
reading amazingly original submissions (shady languages, one-liner like solutions, or solutions using lesser-known features), but also
to learn some things by comparing to my solution (in the same language I used, of course.)\
For example, the average pythoner I am forgot that a list can be indexed backwards without being reversed, writing more succinctly
(but also more idiomatically):

```python
l = [...]
last = l[-1]
```

instead of:
```python
l = [...]
l.reverse()
last = l[0]
```

In particular, I almost daily read Salvatore Sanfilippo's very elegant and thoroughly commented
[C solutions](https://github.com/antirez/adventofcode2022) (you might notice some similarity in my C code.)
If you're into C or looking for beautiful C code read, this is a very good recommendation.

### See also

* [My AoC Github repository](https://github.com/n-eq/advent-of-code)
