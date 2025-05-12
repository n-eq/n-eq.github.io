---
layout: post
title: "Inspecting the memory layout of a Rust blink program for Arduino"
date: 2025-5-12 10:00:00
tags: [rust, arduino, embedded, memory, hal]
---

Unless you prefer to define registers, addresses, and toggle bits manually, the simplest Rust "Blinky" program
for an Arduino Uno board consists of the following:

```toml
# Cargo.toml
[dependencies]
panic-halt = "^1"
# as of May 2025, this crate is not yet published on crates.io
arduino-hal = { git = "https://github.com/Rahix/avr-hal", features = ["arduino-uno"] }
```

```rust
// src/main.rs
#![no_std]
#![no_main]

use panic_halt as _;

#[arduino_hal::entry]
fn main() -> ! {
    let dp = arduino_hal::Peripherals::take().unwrap();
    let pins = arduino_hal::pins!(dp);
    let mut led = pins.d13.into_output();

    loop {
        led.toggle();
        arduino_hal::delay_ms(1000);
    }
}
```

In this post, we'll dig into the underlying Rust code concepts used in this program, we'll
inspect the generated assembly code, and the memory layout of the compiled binary.

## Understanding the code

If you're familiar with the previous snippet, you can skip to the next section. Otherwise, let's break it down:

### no_std
This line tells the Rust compiler not to link the standard library (`std`). 
Instead, we'll only rely on the `core` library, which is a subset of it.
Since we're writing code for an embedded device (that can have a limited amount of memory), we don't
want to include the standard library in our binary, which is designed for general-purpose systems.
This means we won't have access to features like heap allocation, collections, threads, etc.

### panic_halt

The usual panic behavior in Rust is to unwind the stack and return to the caller. This is something that's
included in the standard library. However, since we're `no_std`, we need to define our own panic behavior.
We either need to define our own implementation using the `#[panic_handler]` attribute or use a crate that provides one.
`panic-halt` crate provides a simple panic handler that halts the program when a panic occurs.

### no_main
This line tells the compiler that we don't want to use the default entry point for our program.
Instead, we will define our own entry point using the `#[arduino_hal::entry]` attribute, see below.

### main
`#[arduino_hal::entry]` expands the function into some low-level boilerplate code that sets up the
real entrypoint for the program, this is out of the scope of this post. \
Our `main` function is a function that returns `!`, which means it doesn't return a value, since it...
_never returns_, as in every embedded program. \

The first three lines correspond to the `setup` function of the equivalent Arduino sketch, that it:
```c
void setup() {
    pinMode(13, OUTPUT);
}
```

First, we take ownership of the peripherals on our board by calling `Peripherals::take()`.
This returns a _singleton_ that defines all the accessible peripherals for this particular board
(ADC, GPIOs, EEPROM, SPI, etc.)
Owning a singleton is a great usage of Rust's ownership model, in that we can only have a single
instance of the peripherals at a time. Doing this early on in the program is a good practice,
as it allows us to avoid potential conflicts with other parts of the code that may try to access the peripherals. \
Then, we use the `pins!` macro to get access to the pins of the microcontroller. This macro generates
code that maps the pins to their corresponding registers and bit positions. \
Depending on the hardware architecture, each pin can be only be configured in a set of given modes.
In our case, we configure pin 13 (mapped to the builtin LED on Arduino Uno boards) as an output.

### loop

Unsuprisingly, at the end of our main function, we have a loop that toggles the LED with a 1s
delay.

## Inspecting the memory layout

Now that we understand the code, let's inspect the compiled binary. The project was configured to strip symbols,
and to optimize for size (using `strip` and `opt-level` fields in the `Cargo.toml` file, and
[the corresponding documentation](https://doc.rust-lang.org/cargo/reference/profiles.html#optimizing-for-size)).

Before digging deeper, let's see how much memory our program uses.

```bash
$ avr-size target/avr-none/debug/blinky.elf
   text	   data	    bss	    dec	    hex	filename
    262	      0	      1	    263	    107	target/avr-none/debug/blinky.elf
```

Our compiled code is only 262 bytes long (text), which is pretty efficient compared to the same
program written as an Arduino sketch compiled with `arduino-cli`:

```bash
$ arduino-cli compile -b arduino:avr:uno
...
$ avr-size blink.ino.elf
   text	   data	    bss	    dec	    hex	filename
    924	      0	      9	    933	    3a5	blink.ino.elf
```

Although the sketch was built with the default configuration (which uses `-Os` to optimize for size),
its footprint is still way bigger than the Rust version. This is probably due to the fact that the
compilation process also uses `-g` to produce debugging information. I'm not sure if there any other
things to consider and didn't investigate further, if you happen to have the answer, please let me know.

There is one thing noteworthy, however, in the size breakout of the Rust program: The `bss` segment
(used to store statically allocated variables) contains 1 byte of data, but our program doesn't
declare any static variables.

Going down the rabbit hole led me to find the **only** static variable in our binary. Remember the
`.take()` call on peripherals? How does it work exactly? \
Under the hood, `avr-device` keeps track of a global static boolean flag to indicate whether the
peripherals have been taken or not. That's the only memory runtime overhead we have in our program.
We'll see the full implementation in the last section.

```rust
pub(crate) static mut DEVICE_PERIPHERALS: bool = false;
```

## Going one layer deeper

Let's now focus on the text segment of our program, the real size of the compiled code. In our case,
the text segment is 262 bytes long (roughly 13% of the available 2kB of RAM on the ATmega328p.)

To understand how things work, we'll need to look at the assembly code generated by the compiler.
For that, we can use `avr-objdump` to disassemble our binary:

```bash
# for convenience, we'll store the output in a file
$ avr-objdump -d target/avr-none/debug/blinky.elf > blinky.S
```

I tried the `-S` option to get the source code interleaved with assembly instructions, but it didn't
yield any interesting results, if you know the reason please let me know!

We can first verify that the disassembled code has the same size as the text segment.

```bash
$ tail -n 5 blinky.S
  f8:	0e 94 7e 00 	call	0xfc	;  0xfc
  fc:	0e 94 80 00 	call	0x100	;  0x10
 100:	ff cf       	rjmp	.-2     ;  0x100
 102:	f8 94       	cli
 104:	ff cf       	rjmp	.-2     ;  0x104
```

According to `avr-size`, the text segment is 262 (0x106) bytes long. In the disassembled code,
the last instruction is at address 0x104 and is 2 bytes long, which gives the same result.

In the remaining of this post, we'll try to breakdown the assembly code and understand how
and what instructions are generated by the compiler.

### Startup

In embedded systems, the first piece of software to execute after a system reset is called the
reset handler. Typically, it is in charge of setting up configuration data 
(e.g. initializing stack pointers) before calling user code. \
With the current example, this is pretty straightforward. The datasheet lists 26 vectors
in the interrupt vector table (the first one being the reset vector.)
In the disassembled code, each of the first 26 instructions is a jump to the address of the
corresponding interrupt handler. In particular, address `0x68` is the start of
our program.
The next 25 instructions contain jumps to each interrupt handler. However, they all point
to the same address `0x8c: jmp 0x0`. This makes sense, since we don't need any interrupt in our program, they
are left to their default value, which is `0x0`. Basically, this means if any interrupt occurs,
it will reset the program.

```
00000000 <.text>:
   0:	jmp	0x68	;  0x68
   4:	jmp	0x8c	;  0x8c
   8:	jmp	0x8c	;  0x8c
   c:	jmp	0x8c	;  0x8c
  10:	jmp	0x8c	;  0x8c
  14:	jmp	0x8c	;  0x8c
  ...
  64:	jmp	0x8c	;  0x8c
```

For the reference, defining an interrupt handler using `avr-device` would look like this for
example:

```rust
#[avr_device::interrupt]
fn USART_RX() {
    // ...
}
```

### Initialization

Reset handler spans from 0x68 until 0x72.
```
  68:	eor	r1, r1
  6a:	out	0x3f, r1
  6c:	ldi	r28, 0xFF
  6e:	ldi	r29, 0x08
  70:	out	0x3e, r29
  72:	out	0x3d, r28
```

The first two instructions clear SREG (AVR status register) by XORing r1 with itself, and storing
the result in it. The remaining instructions initialize stack pointers (registers SPH and SPL), they
are respectively set to 0xFF and 0x08. I couldn't find an exact answer as to how these values are
chosen.

### Program logic

```
  90:	call	0x94
  94:	push	r17
  96:	in	r24, 0x3f
  98:	cli
  9a:	lds	r25, 0x0100
  9e:	cpi	r25, 0x01
  a0:	brne	.+2
  a2:	rjmp	.+74
```

This part corresponds to `let dp = arduino_hal::Peripherals::take().unwrap();`.
Below is the generated source code for `take`:

```rs
pub fn take() -> Option<Self> {
    critical_section::with(|_| {
        if unsafe { DEVICE_PERIPHERALS } {
            return None;
        }
        Some(unsafe { Peripherals::steal() })
    })
}
```

Without going into too much detail, `critical_section::with` will save SREG (status register)
in a temporary register, then disable interrupts (`cli`).
Then, the `DEVICE_PERIPHERALS` static variable is checked to see if the peripherals have already
been taken. This informs us that the variables is stored at `0x0100`, that is at the start of SRAM
addressable space.

Finally, upon failure, the call to `unwrap` will abort the program, that is why there is
an `rjmp` instruction with a relative offset of +74 (towards 0x100) if the previous comparison
failed. Otherwise, the program follows along by skipping the next instruction (`brne .+2`).

```
  a4:	ldi	r25, 0x01
  a6:	sts	0x0100, r25
  aa:	out	0x3f, r24
```

When the program continues, the next instructions simply take care of setting `DEVICE_PERIPHERALS`,
and restoring the value of SREG.

```
  ac:	cbi	0x05, 5
  ae:	sbi	0x04, 5
```

What comes next is more interesting. \
`cbi` (Clear Bit in I/O register) and `sbi` (Set Bit in I/O register)
respectively **unsets** bit 5 in PORTB (Port B Data Register), and **sets** bit 5 in DDRB
(Data Direction Register B.)
Since we use the builtin LED, we know it's mapped to pin 5 on port B. \
As a result, the two instructions perform the following:
1. Turn off PB5, most probably for sanity
2. Set PB5 as output

Starting from address `b0`, we know we're in the infinite loop but things
get more complicated to understand. It's difficult to figure exactly why the instructions
get generated since `arduino-hal` crate uses `embedded-hal` to implement a busy wait delay
for the given duration.


## Further note on toggle

## References

- ATmega328p datasheet: <https://ww1.microchip.com/downloads/en/DeviceDoc/Atmel-7810-Automotive-Microcontrollers-ATmega328P_Datasheet.pdf>
- AVR instruction set manual: <https://ww1.microchip.com/downloads/en/devicedoc/AVR-Instruction-Set-Manual-DS40002198A.pdf>
- Arduino HAL crate: <https://github.com/Rahix/avr-hal>
- AVR microcontrollers peripheral access crate: <https://github.com/Rahix/avr-device>
