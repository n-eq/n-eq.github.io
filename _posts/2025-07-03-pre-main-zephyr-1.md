---
layout: post
date: 2025-07-03
title: "Pre-main rituals: How Zephyr prepares Cortex-M CPUs"
excerpt: "Before main() ever runs, Zephyr executes a carefully crafted boot sequence on ARM Cortex-M CPUs.
The first part of this blog series breaks down the reset handler, vector table, and early startup logic."
tags: [zephyr-pre-main, zephyr, embedded, assembly, arm, cortex-m, low-level, walkthrough]
---


Pre-`main` source files are something you hardly ever have to worry about. More often than not,
you'll be using pre-existing files that you don't need to modify or even understand deeply. They're
frequently copied from one project to another without change. It's rare that you need to dive into
their contents, but when you do they can reveal a lot about how your system actually works.

In this post, we'll cover Zephyr Project's startup process on ARM Cortex-M CPUs, focusing on its
early assembly code and vector table.


## Setup

We’ll use the Arduino Nano 33 BLE board. The Zephyr source code referenced here is based on commit
55db18, from Monday, June 23rd. This post assumes some familiarity with embedded systems, and
assembly programming.

## First stop: the bootloader

Although it's not at the heart of this post, it's worth saying a few things about the bootloader.
The Nano 33 comes with a [BOSSA](https://github.com/arduino/BOSSA)-compatible
[bootloader](https://github.com/arduino/ArduinoCore-nRF528x-mbedos/tree/master/bootloaders/nano33ble).
BOSSA (Basic Open Source SAM-BA Application) is a flash programming utility initially developed for
Atmel's SAM family. It was forked and adapted by Arduino to support nRF52840 + USB CDC. In practice,
the bootloader enables flashing a new application through USB CDC (Communications Device Class) by
double-tapping the onboard button, and then calling `bossac` with the binary to upload.

On the Zephyr side, we can clearly see two config variables defined in our board's default
configuration file `boards/arduino/nano_33_ble/arduino_nano_33_ble_defconfig`:

```conf
CONFIG_BOOTLOADER_BOSSA=y
CONFIG_BOOTLOADER_BOSSA_LEGACY=y
```

They are mainly used in the Python runner scripts called by `west` (Zephyr’s meta-build tool, see my
[dedicated article]({% post_url 2025-06-03-zephyr-build-101 %}).)

For this particular board, the bootloader is instrumental in uploading a new firmware to the board.
But we're more interested in user code and the process that leads into executing it.

## In the beginning was the reset handler

Whenever an ARM Cortex-M CPU gets powered on, it automatically executes the reset handler function,
which is located at the very top of the vector table, a table of pointers (function addresses)
starting at a known location in memory, typically `0x0`, unless overriden by VTOR (Vector Table
Offset Register.)

Since we now deal directly with the CPU (in this case, ARM Cortex M4F), we'll be looking for source
code under `arch/arm/core/cortex_m`.

`vector_table.S` is a relatively small assembly file that can be broken down into the following:

```c
SECTION_SUBSEC_FUNC(exc_vector_table,_vector_table_section,_vector_table)
```

Like every big project, Zephyr makes extensive use of macros. In particular, the one above
expands into placing the data that follow inside the `.vector_table` section, so the CPU can find it at boot.

```asm
.word z_main_stack + CONFIG_MAIN_STACK_SIZE
```

This first instruction defines the first word in the vector table, which corresponds, according to
the
[docs](https://developer.arm.com/documentation/107565/0101/Use-case-examples/Generic-Information/What-is-inside-a-program-image-/Vector-table),
to the stack pointer.

```asm
.word z_arm_reset
```

Next is the reset handler address. A very important piece, since as the name suggests, the CPU jumps
here after reset. In this case, the reset handler is set to be the symbol `z_arm_reset`. We will
focus on this in the next sections.

The next two lines have the same purpose. They define Zephyr handler functions for respectively the
NMI (Non-Maskable Interrupt) and hard fault exceptions.

What follows is where the vector table diverges depending on the ARM architecture version. The only
thing to notice is that ARMv6-M (used in Cortex M0, M0+ and M1) and ARMv8-M Baseline (used in Cortex
M23, M33 and M35P) have fewer exceptions, so many entries in the vector table are left undefined
(`.word 0`). For newer architecture versions, we can find implementations for the handlers
corresponding to each of the possible exceptions (bus fault, secure fault, etc.)

## Close lookup on the reset handler

Moving forward, let's get a closer look at `z_arm_reset`. A quick grep and we find out that the
symbol is defined inside `arch/arm/core/cortex_m/reset.S`. At the top you'll see a helpful comment
that makes understanding even easier.

```asm
SECTION_SUBSEC_FUNC(TEXT,_reset_section,z_arm_reset)
SECTION_SUBSEC_FUNC(TEXT,_reset_section,__start)
```

Just like the vector table, these two macros place the `z_arm_reset` and `__start` (an alias of the
former) labels in a subsection of `.text` (code segment), named `.text._reset_section`, possibly for
allowing finer-grained control during the linking step.


### Miscellaneous initialization (specific to bootloader-less applications)

```asm
#if defined(CONFIG_INIT_ARCH_HW_AT_BOOT)
    /* Reset CONTROL register */
    movs.n r0, #0
    msr CONTROL, r0
    isb
#if defined(CONFIG_CPU_CORTEX_M_HAS_SPLIM)
    /* Clear SPLIM registers */
    movs.n r0, #0
    msr MSPLIM, r0
    msr PSPLIM, r0
#endif /* CONFIG_CPU_CORTEX_M_HAS_SPLIM */
#endif /* CONFIG_INIT_ARCH_HW_AT_BOOT */
```

At this stage, it's handy to check whether a macro is defined in your build config. There are
multiple ways to do so:

- `grep CONFIG_NAME build/zephyr/.config`
- `grep CONFIG_NAME build/zephyr/include/generated/zephyr/autoconf.h`
 
In my particular case, neither `CONFIG_INIT_ARCH_HW_AT_BOOT` nor `CONFIG_CPU_CORTEX_M_HAS_SPLIM` are
defined. These are typically enabled when you boot without a bootloader. Otherwise, that piece of
code has already done these initializations, so Zephyr's reset handler skips it.

```asm
#if defined(CONFIG_PM_S2RAM)
ldr r0, =z_interrupt_stacks + CONFIG_ISR_STACK_SIZE + MPU_GUARD_ALIGN_AND_SIZE
msr msp, r0
bl arch_pm_s2ram_resume
#endif /* CONFIG_PM_S2RAM */
```

`PM_S2RAM` stands for suspend-to-RAM. When enabled, this configuration temporarily sets the reset
handler to the interrupt stack for the duration of the resume logic (performed in
`arch_pm_s2ram_resume`).

But again, if your application is using a bootloader, this section is also skipped.

### Main stack setup 

```asm
ldr r0, =z_main_stack + CONFIG_MAIN_STACK_SIZE
msr msp, r0
```

These two instructions set MSP (Main Stack Pointer) to `z_main_stack + CONFIG_MAIN_SIZE`. If you've
been reading carefully, you might have noticed the same thing is also done in `vector_table.S` at
offset `0`:

```asm
.word z_main_stack + CONFIG_MAIN_STACK_SIZE
```

And you're... right. However, although the two instructions do the same thing, they're not
redundant, and don't serve the same purpose.

Both lines set MSP, but they serve distinct purposes:
- The vector table's entry is used by the CPU at power-on-reset.
- The `msr msp` instruction is used at runtime to ensure the value in MSP is correct, typically
  after bootloader handoff.

### Post-Kernel flag clear

```asm
#if defined(CONFIG_DEBUG_THREAD_INFO)
    /* Clear z_sys_post_kernel flag for RTOS aware debuggers */
    movs.n r0, #0
    ldr r1, =z_sys_post_kernel
    strb r0, [r1]
#endif /* CONFIG_DEBUG_THREAD_INFO */
```

The next part is another setup for debuggers, the comment is self-explanatory so no need to
elaborate.


### SoC Hook

```asm
#if defined(CONFIG_SOC_RESET_HOOK)
bl soc_reset_hook
#endif
```

It's not always clear in which cases this configuration variable is
used/defined. However, for Nordic MCUs (The Nano 33 embeds the nRF52840), you can find this line:

```asm
# soc/nordic/common/CMakeLists.txt
zephyr_linker_symbol(SYMBOL soc_reset_hook EXPR "@SystemInit@")
```

It's a symbol aliasing trick which instructs the linker script generator to resolve `soc_reset_hook`
(a weak symbol) to `SystemInit` when it hasn't been defined. From there, we can guess it's
everything related to resetting peripherals, setting up clock trees, etc.

### Disabling the MPU

```asm
#if defined(CONFIG_INIT_ARCH_HW_AT_BOOT)
#if defined(CONFIG_CPU_HAS_ARM_MPU)
    /* Disable MPU */
    movs.n r0, #0
    ldr r1, =_SCS_MPU_CTRL
    str r0, [r1]
    dsb
#endif /* CONFIG_CPU_HAS_ARM_MPU */

    /* Initialize core architecture registers and system blocks */
    bl z_arm_init_arch_hw_at_boot
#endif /* CONFIG_INIT_ARCH_HW_AT_BOOT */
```

In certain configurations, the reset handler clears MPU `CONTROL` register, disabling memory protection
(temporarily).

### Interrupt masking

```asm
#if defined(CONFIG_ARMV6_M_ARMV8_M_BASELINE)
    cpsid i
#elif defined(CONFIG_ARMV7_M_ARMV8_M_MAINLINE)
    movs.n r0, #_EXC_IRQ_DEFAULT_PRIO
    msr BASEPRI, r0
#else
#error Unknown ARM architecture
#endif
```

Depending on the Cortex-M variant this code masks interrupts. They're re-enabled when the CPU
switches to the main thread.

### Watchdog setup

```asm
#ifdef CONFIG_WDOG_INIT
    /* board-specific watchdog initialization is necessary */
    bl z_arm_watchdog_init
#endif
```

Early watchdog setup is very rare. That's why only a few platforms _**do**_ define
`CONFIG_WDOG_INIT`, and thus provide an implementation of `z_arm_watchdog_init`. As far as I can
tell, it's NXP's KE1xF and S32K1 microcontrollers.


### Stack painting

```asm
#ifdef CONFIG_INIT_STACKS
    ldr r0, =z_interrupt_stacks
    ldr r1, =0xaa
    ldr r2, =CONFIG_ISR_STACK_SIZE + MPU_GUARD_ALIGN_AND_SIZE
    bl z_early_memset
#endif
```

What follows is known as "stack painting", where the OS fills the stack RAM segment with a known
pattern. Zephyr uses the ad-hoc value `0xAA`, FreeRTOS for instance uses `0xA5` instead. One use
case of this mechanism is detecting stack overflows, or simply knowing stack usage of a given task
(using the dedicated `k_thread_stack_space_get` method.)

### Last step before jumping to C runtime

```asm
ldr r0, =z_interrupt_stacks
ldr r1, =CONFIG_ISR_STACK_SIZE + MPU_GUARD_ALIGN_AND_SIZE
adds r0, r0, r1
msr PSP, r0
mrs r0, CONTROL
movs r1, #2
orrs r0, r1 /* CONTROL_SPSEL_Msk */
msr CONTROL, r0

isb
```

Prior to calling C runtime code, ARM Cortex-M reset handler also takes care of setting and switching
to PSP (Process Stack Pointer). In the instructions above, this is done by setting bit 1 of
[CONTROL](https://developer.arm.com/documentation/107656/0101/Registers/Special-purpose-registers/CONTROL-register)
register, telling the processor to use PSP instead of MSP.

The last instruction (`isb`: Instruction Synchronization Barrier) is a context synchronization
event that ensures all previous instructions are completed before executing any further ones, and is
typically used when changing `CONTROL` register bits.

After this sequence:
- Thread mode uses the PSP pointing to the top of the interrupt stack.
- MSP is still set to `z_main_stack + CONFIG_MAIN_STACK_SIZE`, and is reserved for interrupts and
  faults.

### Handing off to C

```asm
bl z_prep_c
```

The final instruction in reset handler code is a plain jump to `z_prep_c`, which we'll cover in the
next article.

It's worth noting that, interestingly, `bl` (branch with link) is chosen instead of `b` – which
makes more sense since we don't expect to return after the call to `z_prep_c` – because it has
a larger jump range than `b` that can be limited on some smaller instruction sets.
