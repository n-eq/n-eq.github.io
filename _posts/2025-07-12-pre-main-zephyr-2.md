---
layout: post
date: 2025-07-12
title: "Pre-main rituals: Zephyr Cortex-M startup file compiler and linker tricks"
excerpt: "A deep dive into Zephyr’s C runtime startup sequence on ARM Cortex-M:
how macros and linker sections enable elegant stage-based function registration."
tags: [zephyr-pre-main, zephyr, rtos, embedded, C, arm, cortex-m, low-level, walkthrough, linker]
---

_This is the second post in our [pre-main Zephyr series]({{ "/tags.html#zephyr-pre-main"
| relative_url }})._

[Last time]({% post_url 2025-07-03-pre-main-zephyr-1 %}), we explored the resources Zephyr uses to
bring up ARM Cortex-M CPUs after a reset. In particular, we examined the vector table, and reset
handler assembly code.\
Today, we dig into the C runtime logic that eventually leads to calling the
application's `main()` function. We'll focus on how Zephyr uses preprocessor macros, linker script
tricks, and GNU C's `__attribute__` mechanism to efficiently register and invoke initialization functions
at different stages of the boot process.

---

The last instruction in the ARM Cortex-M reset handler is `bl z_prep_c`, let's walk though the
called function step-by-step.

## 1. [Config-specific] `soc_prep_hook()`

The function starts with an optional call to `soc_prep_hook`, gated on `CONFIG_SOC_PREP_HOOK` config
variable. When defined, this function performs very-early pre-main initializations, e.g.: clock
selection, TrustZone setup, etc.

## 2. Vector table relocation

Next, Zephyr ensures the vector table is located at the right address by calling
`relocate_vector_table`. This is done regardless of the configuration and architecture, and is
necessary to reset `VTOR` register to point to Zephyr's own table, so that future interrupts and
faults hit the correct handlers.

We can verify the address of the vector table in our output ELF file, confirming that the vector
table effectively starts at `0x10000`:

```bash
$ arm-none-eabi-objdump -t build/zephyr/zephyr.elf | grep _vector_table -w
00010000 g     O rom_start	00000000 _vector_table
```

In `build/zephyr/linker.cmd` too, we can double-check that the firmware, thus the vector table,
starts at the same address:

```
 OUTPUT_FORMAT("elf32-littlearm")
_region_min_align = 32;
MEMORY
    {
    FLASH (rx) : ORIGIN = (0x0 + 0x10000), LENGTH = (0xe8000 - 0x0)
    ...
```

## 3. [Config-specific] Floating Point Unit initialization

Zephyr then enables the Floating Point Unit (FPU) on CPUs that have it (Cortex-M4F, M7F, M33F, M35PF). It is
important to perform this setup early enough – i.e. before any FP-related instructions are run –
to avoid triggering usage faults.

## 4. BSS zeroing

The next step is standard in any C runtime startup. `z_bss_zero` takes care of clearing
the `.bss` section, where all uninitialized global and static variables live. It is more or less
equivalent to:

```c
memset(&_bss_start, 0, &_bss_end - &_bss_start);
```

## 5. Data copy

Likewise, Zephyr performs another very common operation in C runtime startup logic. It copies the
initialized data section (`.data`) from flash to RAM, which roughly corresponds to:

```c
for (dest = &_data_start; dest < &_data_end; ++dest)
    *dest = *src++; // where src = image_load_addr
```

This is particularly important to ensure initialized global variables are copied to RAM before
executing user code.

## 6. Interrupt controller initialization

Following this, Zephyr either calls the SoC's custom interrupt controller init function
(`z_soc_irq_init`) when defined, or uses the default fallback `z_arm_interrupt_init`. Here's the
definition from `arch/arm/core/cortex_m/irq_init.c`:

```c
void z_arm_interrupt_init(void) {
	int irq = 0;

#if defined(CONFIG_MULTI_LEVEL_INTERRUPTS) && defined(CONFIG_2ND_LVL_ISR_TBL_OFFSET)
	for (; irq < CONFIG_2ND_LVL_ISR_TBL_OFFSET; irq++) {
#else
	for (; irq < CONFIG_NUM_IRQS; irq++) {
#endif
		NVIC_SetPriority((IRQn_Type)irq, _IRQ_PRIO_OFFSET);
	}
}
```

The function is basically a loop over all IRQs.\
In a multi-level interrupt controller, only the first level is initialized here (indices up to
`CONFIG_2ND_LVL_ISR_TBL_OFFSET`), the remaining IRQs are SoC-specific. Regardless of the config,
Zephyr initializes all the IRQs using CMSIS's `NVIC_SetPriority`, with all their priority levels set
to `_EXC_IRQ_DEFAULT_PRIO`, ensuring they can be enabled safely and will run in a predictable order
unless overridden later.

## 7. [Config-specific] Cache init

Most ARM Cortex-M CPUs don't have data/instruction cache, so this step is skipped.
Instruction and/or data cache can only be present optionally in Cortex-M7 and M35P.
In this step, Zephyr calls the generic `arch_cache_init` function, which is empty
by default on Cortex-M families, even when it's present. Instead, cache control
is left to the SoC vendor’s implementation, as we'll see in the next article.

## 8. [Config-specific] Trapping null pointer dereferences

When `CONFIG_NULL_POINTER_EXCEPTION_DETECTION_DWT` is set, Zephyr calls
`z_arm_debug_enable_null_pointer_detection` which uses the ARM DWT (Data Watchpoint and Trace) unit
to trap null pointer dereferences.

For ARMV8-M Mainline, it uses two DWT comparators to monitor illegal (and not just `NULL`)
dereferences in the address space spanning from `0x0` to `CONFIG_NULL_POINTER_EXCEPTION_DETECTION_DWT`,
the size of paged "unmapped" (defaults to `0x400`).

For the remaining cases (ARMv7-M processors, or processors using a backwards-compatible ARMv8-M
processor implementation supporting Main Extension), a comparator and a mask are used.\
The result is still the same though: If any illegal R/W access is performed in the range `[0,
CONFIG_NULL_POINTER_EXCEPTION_DETECTION_DWT]`, an exception occurs.

This feature is very useful and can help detect null pointer bugs that occur very early during
execution.

## Kernel initialization

The last bit is a call to `z_cstart`. This is a non SoC-specific function located in `kernel/init.c`
that marks the transition from platform startup to Zephyr RTOS initialization, let's dive into its
key elements.

First, `z_sys_init_run_level` is called in order to initialize baselevel devices. This function is
called multiple times inside `z_cstart`, and has an important role so let's unpack it in details.

The source code of the function is fairly easy to understand regardless of the context. It can be
summarized as follows:

1. The function accepts an enum parameter `level`.
2. It defines a static list `levels` of type:
```c
struct init_entry {
    int (*init_fn)(void);
    const struct device *dev;
}
```
3. Based on `level`, it calls `do_device_init(entry->dev)` for entries in the list that correspond to
  the requested level if they're device drivers (which is never the case for `EARLY` initialization
  level), or `entry->init_fn()` otherwise.

At this stage, we can ask a few questions:
- How does `levels` array work and why is it `static`ally declared?
- How are entries defined?

Zephyr defines a set of "levels" of initializations; you can see them as a multistage rocket: each
level is initialized in order: early initialization, then pre-kernel, post-kernel,
application, and eventually the final level.

For each level, a set of functions are "attached".\
After its definition, a function named
`my_init_function` defined as an init function performs the following preprocessor macro call:

```c
SYS_INIT(my_init_function, 3 /* LEVEL */, 5 /* PRIO */);
```

which ultimately expands, after a few operations, to this **very verbose** definition:

```c
static const __aligned(__alignof(struct init_entry)) struct init_entry
__attribute__((__section__("z_init_POST_KERNEL_P_5_SUB_0_")))
__attribute__((__used__))
__attribute__((no_sanitize("address")))
__init_my_init_function = {
    .init_fn = (my_init_function),
    .dev = ((void *)0)
};
```

In this definition lie most answers to our previous questions. In particular, this is a very
insightful illustration of the power of `__attribute__` keyword. Let's see what purpose each
of them serves:

- `__attribute__((no_sanitize("address")))` disables Address Sanitizer (ASan) to avoid false
  positives or runtime overhead for this very "low-level" variable. It is only relevant when
  `-fsanitize=address` is used in compiler flags.
- `__attribute__((__used__))` tells the compiler not to discard the variable even if it looks
  unused. This is even more important if we know that when the variable is declared as `static` (which is the
  case here), the compiler may optimize it away.
- `__attribute__((__section__(".z_init_POST_KERNEL_P_5_SUB_0_")))` is the key attribute to help
  understand this definition. \
  It instructs the compiler to place this variable in a custom linker section named
  `.z_init_POST_KERNEL_P_5_SUB_0_`, allowing the linker script, as we'll see, to aggregate init
  entries per level and priority into a contiguous block. Without this, Zephyr wouldn’t find it
  easily at runtime.

The last point is exactly how everything fits together. If we inspect the linker script
(reminder: it's `build/zephyr/linker.cmd`), we'll see this:

```asm
 initlevel :
 {
  __init_start = .;
  __init_EARLY_start = .; KEEP(*(SORT(.z_initin _EARLY_P_?_*))); KEEP(*(SORT(.z_init_EARLY_P_??_*))); KEEP(*(SORT(.z_init_EARLY_P_???_*)));
  __init_PRE_KERNEL_1_start = .; KEEP(*(SORT(.z_init_PRE_KERNEL_1_P_?_*))); KEEP(*(SORT(.z_init_PRE_KERNEL_1_P_??_*))); KEEP(*(SORT(.z_init_PRE_KERNEL_1_P_???_*)));
  __init_PRE_KERNEL_2_start = .; KEEP(*(SORT(.z_init_PRE_KERNEL_2_P_?_*))); KEEP(*(SORT(.z_init_PRE_KERNEL_2_P_??_*))); KEEP(*(SORT(.z_init_PRE_KERNEL_2_P_???_*)));
  __init_POST_KERNEL_start = .; KEEP(*(SORT(.z_init_POST_KERNEL_P_?_*))); KEEP(*(SORT(.z_init_POST_KERNEL_P_??_*))); KEEP(*(SORT(.z_init_POST_KERNEL_P_???_*)));
  __init_APPLICATION_start = .; KEEP(*(SORT(.z_init_APPLICATION_P_?_*))); KEEP(*(SORT(.z_init_APPLICATION_P_??_*))); KEEP(*(SORT(.z_init_APPLICATION_P_???_*)));
  __init_SMP_start = .; KEEP(*(SORT(.z_init_SMP_P_?_*))); KEEP(*(SORT(.z_init_SMP_P_??_*))); KEEP(*(SORT(.z_init_SMP_P_???_*)));
  __init_end = .;
 } > FLASH
```

We can conclude that `my_init_function`, which ended up being manually put in
`.z_init_POST_KERNEL_P_5_SUB_0_`, will be matched by the pattern:

```asm
KEEP(*(SORT(.z_init_POST_KERNEL_P_???_*)))
```

and thus inserted (sorted by name, i.e. by priority) into `__init_POST_KERNEL_start`, which belongs
to the parent section `initlevel`.

One more thing: why is `levels` variable statically defined inside the function? We can make a few
guesses:
- No other part of the code needs to access it. By keeping it local, it helps reduce its scope and
  avoid cluttering the global symbol table.
- No stack allocation needed. Instead, the compiler can store it in `.rodata` segment.

It could have been that the array is declared as `static` within the function to allow for link-time
optimizations (LTO) in the cases when `z_sys_init_run_level` is never called (due to preprocessor
macros and Kconfig definitions), but this never happens.

---

We can now clearly see how the levels array ties directly into the linker script. The
`__init_*_start` symbols are linker-defined pointers to arrays of `init_entry` structs, each sorted
into their corresponding `.z_init_*` section during compilation.\
At runtime, `z_sys_init_run_level`
walks through each section for a given level and calls the associated initialization functions. This
design allows Zephyr to cleanly organize startup logic into very well-defined stages.

In the next post, we’ll look at how `z_cstart` finishes the remaining setup,
configures threads and finally hands control off to `main()`.
