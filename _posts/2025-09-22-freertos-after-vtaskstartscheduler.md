---
layout: post
title: "What happens after you call vTaskStartScheduler?"
date: 2025-09-22
tags: [freertos, firmware, rtos, C, walkthrough]
excerpt: "How does FreeRTOS prepare the stack, configure interrupts, and use an SVC call to launch your first task?"
---

FreeRTOS is an amazing tool for building simple yet powerful embedded systems.
But at its core, it’s surprisingly minimal; if you forget about the middleware,
drivers, toolchain stuff, you're only left with a `main()` function that
defines (directly or indirectly) a couple of tasks, maybe some timers — and
it'll often end with a notorious function call: `vTaskStartScheduler()`.\
So what actually happens when you call it? Let’s peel back the layers.

## What happens _before_

Before ever reaching `vTaskStartScheduler`, the code needs to go through
`main()`. But even before that, the CPU follows the well-defined boot sequence
common to ARM Cortex-M device family: it jumps to the reset handler and some
low-level magic happens that takes care of a few important things: initializing
memory, the stack (pointer), and other bare-metal groundwork to make C code
runnable, we won't get into too many details on this part.

Following this, there's still no scheduler, nor any tasks, only a raw CPU ready to execute
instructions.

## `main()` handoff

As soon as the C runtime is initialized, the CPU jumps to `main()`, which is responsible of spawning
tasks using `xTaskCreate()` API, before eventually calling `vTaskStartScheduler()` after all tasks
have been created (_but not yet **launched**_).

Creating tasks is almost always done using `xTaskCreate()`, but those who have wandered in
FreeRTOS's source code or read the docs, should know that using this function requires
`configSUPPORT_DYNAMIC_ALLOCATION` to be left undefined, or set to 1 in FreeRTOSConfig.h, otherwise
the function will not be found by the compiler. A lesser-known alternative exists, though, which is
to manually allocate a stack for the task being created, and use it as an argument of
`xTaskCreateStatic`[^1].

## What does `xTaskCreate()` do?

In the "classic" version (with dynamic allocation), the function will define and fill a "Task
Control Block" structure (`typedef struct tskTaskControlBlock { .. } tskTCB;`) that will hold all
sort of relevant information to represent and update the stack during the lifetime of the program.
At this stage, FreeRTOS only defines a handful of fields in the allocated struct: name, priority,
handler function, etc. At the end, the new task control block structure is added to the list of
ready tasks:

```c
prvAddNewTaskToReadyList( pxNewTCB );
```

The ready list is a list of `configMAX_PRIORITIES`, where each element is a list itself. Any new
task is queued at the end of the list which index corresponds to its defined priority.

## Unveiling `vTaskStartScheduler()`

Early on, `vTaskStartScheduler` takes care of queueing the idle task. It is necessary for the
scheduler to have at least one task ready anytime during program lifetime, especially if the user
didn't spawn any task before calling the function:

```c
  /* Add the idle task at the lowest priority. */
  #if( configSUPPORT_STATIC_ALLOCATION == 1 )
  {
        // ...
  }
  #else
  {
    /* The Idle task is being created using dynamically allocated RAM. */
    xReturn = xTaskCreate(  prvIdleTask,
                configIDLE_TASK_NAME,
                configMINIMAL_STACK_SIZE,
                ( void * ) NULL,
                portPRIVILEGE_BIT,
                &xIdleTaskHandle );
  }
  #endif /* configSUPPORT_STATIC_ALLOCATION */
```

Next, the function is also responsible for creating the
[timer](https://www.freertos.org/Documentation/02-Kernel/02-Kernel-features/05-Software-timers/01-Software-timers)
task:

```c
xReturn = xTimerCreateTimerTask();
```

After a call to the optionally user-defined `freertos_tasks_c_additions_init()` comes the most
interesting part:

```c
  // comments were deleted for brevity
  portDISABLE_INTERRUPTS();

  #if ( configUSE_NEWLIB_REENTRANT == 1 )
  {
    _impure_ptr = &( pxCurrentTCB->xNewLib_reent );
  }
  #endif /* configUSE_NEWLIB_REENTRANT */

  xNextTaskUnblockTime = portMAX_DELAY;
  xSchedulerRunning = pdTRUE;
  xTickCount = ( TickType_t ) configINITIAL_TICK_COUNT;

  portCONFIGURE_TIMER_FOR_RUN_TIME_STATS();

  traceTASK_SWITCHED_IN();

  if( xPortStartScheduler() != pdFALSE ) { }
  else { }
```

### Interrupt masking

First, interrupts are disabled. This is a safety mechanism used to ensure no tick interrupts fire
before the first task starts, and as result to prevent race conditions or undefined behavior.
A comment above the call rightfully explains that:

> _the stacks of the created tasks contain a status word with interrupts switched on so interrupts
will automatically get re-enabled when the first task starts_.

### Newlib specific config

For ports using Newlib, each task gets its own `xNewLib_reent` structure to ensure thread-safe
function calls. The function sets `__impure_ptr` to point to that of the current task (the one that
will first execute).

### Tracing and global variables update

FreeRTOS then proceeds to define a couple of global variables: global tick counter, and scheduler
state (running), besides calling functions dedicated to stats and tracing.

### xPortStartScheduler

This is the key call where port-specific code takes control. The implementation of this function
can be found inside `FreeRTOS/portable/**/**/port.c` depending on the toolchain and target.

In the case of a Cortex-M4 compiled using GCC for example, the function, is defined in
`portable/GCC/ARM_CM4F/port.c`.

If `configASSERT` is defined, the function performs some early sanity checks, we won't get into that
as it's not really relevant for this article.

```c
portNVIC_SYSPRI2_REG |= portNVIC_PENDSV_PRI;
portNVIC_SYSPRI2_REG |= portNVIC_SYSTICK_PRI;
```

PendSV (the interrupt used to perform context switches) and SysTick (HW interrupt used for system
ticks) are then set to the lowest priority level, so they don't preempt any "real" interrupt
(e.g. UART, SPI, or ADC)

```c
vPortSetupTimerInterrupt();
```

This call starts SysTick by configuring the hardware timer that generates the tick interrupt. The
tick is central in the OS's time base, it's used to:
- wake up delayed tasks
- update system tick count
- trigger context switches

At this point, SysTick becomes configured but still masked because interrupts are globally disabled.

```c
uxCriticalNesting = 0;
```

For out of scope reasons, FreeRTOS tracks how many times code entered a critical section. This
instruction simply resets this global counter to 0.

```c
prvPortStartFirstTask();

static void prvPortStartFirstTask( void )
{
  __asm volatile(
      " ldr r0, =0xE000ED08   \n" /* Use the NVIC offset register to locate the stack. */
      " ldr r0, [r0]          \n"
      " ldr r0, [r0]          \n"
      " msr msp, r0           \n" /* Set the msp back to the start of the stack. */
      " cpsie i               \n" /* Globally enable interrupts. */
      " cpsie f               \n"
      " dsb                   \n"
      " isb                   \n"
      " svc 0                 \n" /* System call to start first task. */
      " nop                   \n"
  );
}
```

Finally, this is where most magic happens:\

At this stage, the scheduler needs to restore the context (i.e. to start) of the first task. On
Cortex-M
CPUs, context switching is done via the PendSV and SVC exceptions. This function arranges the
environment so that an `svc` call can restore the very first task’s context from its stack:

**Assembly breakdown**

* `ldr r0, =0xE000ED08`

Loads the address of the Vector Table Offset Register (VTOR) in the System Control
Block (SCB) into r0.

* `ldr r0, [r0]`

Dereferences VTOR to get the address of the vector table in memory. On reset,
this points to the start of flash (0x0) unless the table is relocated.

* `ldr r0, [r0]`

Reads the first entry in the vector table, which is
the initial Main Stack Pointer (MSP) value used at reset. This is exactly what the CPU itself loads
on reset.

* `msr msp, r0`

Writes that value into the MSP register. It effectively resets the MSP to its initial reset value
(like a soft reset of the stack pointer). FreeRTOS does this to ensure the MSP is clean before switching to the task stacks.

* `cpsie i`

Enables IRQ interrupts.

* `cpsie f`

Enables fault exceptions. Interrupts can now fire (important for SysTick, PendSV, SVC, etc.).

* `dsb; isb`
    
Data Synchronization Barrier and Instruction Synchronization Barrier. Makes sure all previous
writes (e.g., to MSP) are complete before continuing.

* `svc 0`

Triggers the Supervisor Call exception (SVC) with immediate value 0. This is where FreeRTOS
hands control to its SVC handler `vPortSVCHandler`.
That handler will:
* Pop the first task’s saved context from its stack.
* Set the PSP (Process Stack Pointer) to the task’s stack.
* Restore registers and jump into the task function.

* `nop`

Just a filler instruction (never really reached in practice, unless something went
wrong).

### The Big Picture

```
 ┌─────────────────────────────┐
 │ Startup code / Scheduler    │
 │ (no task running yet)       │
 └──────────────┬──────────────┘
                │
                │ 1. Read initial MSP from vector table
                │    and reset MSP register
                ▼
       ┌─────────────────────────┐
       │ MSP now reset           │
       │ (clean main stack)      │
       └─────────┬───────────────┘
                 │
                 │ 2. Enable IRQ and fault exceptions
                 ▼
       ┌─────────────────────────┐
       │ Interrupts globally ON  │
       │ (SysTick, PendSV, SVC)  │
       └─────────┬───────────────┘
                 │
                 │ 3. Execute SVC 0 instruction
                 ▼
       ┌─────────────────────────┐
       │ CPU enters SVC handler  │
       │ (vPortSVCHandler)       │
       └─────────┬───────────────┘
                 │
                 │ 4. SVC handler restores first task context:
                 │    • loads PSP with task stack
                 │    • pops registers, sets PC
                 ▼
       ┌─────────────────────────┐
       │ First FreeRTOS task     │
       │ now running             │
       └─────────────────────────┘

```

## Footnotes

[^1]: `xTaskCreate` was introduced in [FreeRTOS 9](https://www.freertos.org/Documentation/04-Roadmap-and-release-note/02-Release-notes/02-FreeRTOS-V9#creating-tasks-and-other-rtos-objects-using-statically-allocated-ram).
