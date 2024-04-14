---
title: eBPF tail-calls示例
author: 李岩
tags:
  - bpf
  - ebpf
  - tail call
categories:
  - bpf
date: 2023-08-26 12:30:00
---
> 最近在整理一些技术文章。本来希望把涉及ELF的内容整理出来，结果发现太难了。ELF涉及的内容要多很多，如果要把希望整理的内容表述清楚，还需要做一些准备的工作。刚好最近完成了tail-calls 的调研，先把关于eBPF的tail-calls的功能整理下吧。

`eBPF`程序是事件驱动的，这就意味着当目标事件触发后，程序才能执行。考虑这样一个场景：有几个不同的`BPF`程序均挂载在相同的`hook`点上，而执行需要保持一定的顺序。这时就需要借助`tail calls`的功能来实现。
<!--more-->

# 一、tail calls 与 bpf2bpf calls的对比

首先要说明的是，将不同的逻辑分支都放到一个`bpf`程序里是很难进行的，因为`bpf`程序存在严格的限制：比如512B的执行栈。处理逻辑复杂，往往意味着需要使用的结构体就多，很容易就超出了512B的限制，编译时会报类似如下的错误：

```
cd uretprobe && go generate
./uretprobe.c:24:15: error: Looks like the BPF stack limit of 512 bytes is exceeded. Please move large on stack variables into BPF per-cpu array map.
        struct event event = {};
                     ^
./uretprobe.c:24:15: error: Looks like the BPF stack limit of 512 bytes is exceeded. Please move large on stack variables into BPF per-cpu array map.

```

对于使用而言，`tail calls`从一定程度上规避这个问题：使用`bpf_tail_call`跳转（注意，跳转callee函数执行完成后，不会继续执行`caller`剩余的逻辑，而是直接退出）的目标函数，函数内部的栈资源限制计算是独立的，会覆盖调用`caller`的栈帧。而常规的`bpf2bpf call`，调用的`callee`执行完成后，会继续执行`caller`里的代码。而且，512B的限制会对`caller callee`整体生效。如，下述的`bpf2bpf call`是会报错的：

```
struct event {
	u32 pid;      // 4B
	u8 line[256]; // 256B
};

// linux-4.16以前，需要这样声明。4.16新增了真正意义上的函数调用而非inline处理。
// static __always_inline void send_event(ctx) {
static void send_event(struct pt_regs *ctx) {
	struct event event = {};
	event.pid          = bpf_get_current_pid_tgid();
	event.line[0]      = 49;
	bpf_perf_event_output(ctx, &events, BPF_F_CURRENT_CPU, &event, sizeof(event));
}

SEC("uretprobe/bash_readline")
int uretprobe_bash_readline(struct pt_regs *ctx) {
    struct event event = {};
    event.pid          = bpf_get_current_pid_tgid();
    event.line[0]      = 49;
    send_event(ctx); // 这里发起了一个bpf2bpf call
    
    // 如果将line的长度调小，程序能够正常执行。send_event后会继续执行。
    bpf_perf_event_output(ctx, &events, BPF_F_CURRENT_CPU, &event, sizeof(event));

    return 0;
}

```

这里算是笔者目前感知到的主要差异。`tail calls`的特性在`linux-4.2`的版本就上线了。在`centos-8`版本的系统上运行没有问题。

# 二、tail calls 的一个示例

这里附上执行效果和一段示例。笔者构建的场景是使用`uretprobe/bash_readline`作为`hook`点，依据返回字符串长度的奇偶性来触发不同的`bpf function`，分别输出不同的事件。实现效果如下。

```
$ sudo ./uretprobe
2023/08/26 14:34:39 Listening for events..
2023/08/26 14:34:45 /bin/bash:readline return value: ll
2023/08/26 14:34:45 get even event
2023/08/26 14:35:01 /bin/bash:readline return value: ls -l
2023/08/26 14:35:01 get odd event

```

`bpf`代码为：

``` 
char __license[] SEC("license") = "Dual MIT/GPL";
struct event {
    u32 pid;
    u8 line[256];

    u8 mark;
};

struct {
    __uint(type, BPF_MAP_TYPE_PERF_EVENT_ARRAY);
} events SEC(".maps");

// Force emitting struct event into the ELF.
const struct event *unused __attribute__((unused));

// 通过bpf-tail-call只能调用同类型的bpf函数
SEC("uretprobe/bash_readline_odd")
int uretprobe_bash_readline_odd(struct pt_regs *ctx){
    struct event event = {};
    event.pid = bpf_get_current_pid_tgid();
    event.line[0] = 49;
    event.mark = 5;
    bpf_perf_event_output(ctx, &events, BPF_F_CURRENT_CPU, &event, sizeof(event));

    return 0;
}

// 通过bpf-tail-call只能调用同类型的bpf函数
SEC("uretprobe/bash_readline_even")
int uretprobe_bash_readline_even(struct pt_regs *ctx){
    struct event event = {};
    event.pid = bpf_get_current_pid_tgid();
    event.mark = 8;
    event.line[0] = 50;
    bpf_perf_event_output(ctx, &events, BPF_F_CURRENT_CPU, &event, sizeof(event));

    return 0;
}

struct{
    __uint(type, BPF_MAP_TYPE_PROG_ARRAY);
    __uint(key_size, sizeof(u32));
    __uint(value_size, sizeof(u32));
    __uint(max_entries, 1024);
    __array(values, int (void*));
} tail_jmp_table SEC(".maps") = {
    .values = {
    	// 这里的id是可以在用户态通过map update来更新的。由此可以延伸出其他有意思的功能。这里从实际需求直接固定值了。
        [135] = (void*)&uretprobe_bash_readline_odd,
        [146] = (void*)&uretprobe_bash_readline_even,
    },
};

SEC("uretprobe/bash_readline")
int uretprobe_bash_readline(struct pt_regs *ctx) {
    struct event event = {};

    event.pid = bpf_get_current_pid_tgid();
    bpf_probe_read(&event.line, sizeof(event.line), (void *)PT_REGS_RC(ctx));

    event.mark = 3;

    bpf_perf_event_output(ctx, &events, BPF_F_CURRENT_CPU, &event, sizeof(event));
    u8 line_length=0;
    for(line_length=0; line_length<80; line_length++){
        if(event.line[line_length] == 0){
            break;
        }
    }

    if (line_length % 2 == 0){
    	// 偶数调用 uretprobe_bash_readline_even
        bpf_tail_call(ctx, &tail_jmp_table, 146);
    }else{
    	// 奇数调用 uretprobe_bash_readline_odd
        bpf_tail_call(ctx, &tail_jmp_table, 135);
    }


    return 0;
}

```   

以上。周末愉快～

# 三、参考文章
[1] [BPF Architecture](https://docs.cilium.io/en/latest/bpf/architecture/)  
[2] [bpf-helpers](https://man7.org/linux/man-pages/man7/bpf-helpers.7.html)  
[3] [在 ebpf/libbpf 程序中使用尾调用（tail calls）](https://mozillazg.com/2022/10/ebpf-libbpf-use-tail-calls.html)  
[4] [kernel version](https://github.com/iovisor/bcc/blob/master/docs/kernel-versions.md)
