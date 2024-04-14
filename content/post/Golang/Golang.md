---
title: BPF追踪Go程序的挑战
author: 李岩
tags:
  - bpf
  - golang
categories:
  - BPF
date: 2023-06-25 17:08:00
---
> 原文地址[Challenges of BPF Tracing Go](https://blog.0x74696d.com/posts/challenges-of-bpf-tracing-go/)。翻译不尽如人意，继续努力。

# BPF追踪Go程序的挑战
当大家对`Go 1.17`语言调用规约(`function calling convention`)调整带来的性能优化感到兴奋时，我却遗憾的看到`Go 1.17`并没有让`BPF uretprobe`变得可行。事实证明，我还没有完全意识到`Go`的可调整的栈空间会让事情变得多复杂。
<!--more-->

`Go`极短的编译时间使得“输出调试”变得非常便捷。当你知道问题处在一个特定的变量时，往往会随手塞入一个`fmt.Printf`或者`log.Debug`或者`spew.Dump`来观察感兴趣的点。但是我经常工作在一个有状态的系统中，在这样的环境下“输出调试”变
得非常受限。重新编入一个`log`语句并且重启系统，往往意味着丢失掉可能导致异常的状态，并且日志输出可能会带来性能开销并掩盖掉`bug`。在这种背景下，我选择`BPF`工具，比如`bpftrace`，来定位问题。


对应用程序开发者而言，`BPF`的一大强力功能是用户态的动态程序观测，在`uprobe`及`uretprobe`的基础上构建起来。`uprobe`会嵌入一个`BPF`探针在函数被调用的地方，`uretprobe`则会嵌入一个探针在函数返回的地方。


比如，这里是一个使用`C`语言写的程序：

```
int sum(int a, int b){
    return a+b;
}
```

使用如下的`bpftrace`程序可以输出上述程序的参数及返回值。

```
#!/usr/bin/env bpftrace

uprobe:./sum:"sum"
{
    printf("args: %d + %d\n", arg0, arg1);
}

uretprobe:./sum:"sum"
{
    printf("result: %d\n", reg("ax"));
}
```

当我们运行这个`bptrace`脚本是，它会等待我们在另一个终端运行目标`C`程序，然后输出如下内容：

```
$ sudo ./sum.bt
Attaching 2 probes...
args: 2 + 3
result: 5
^C
```

对于一个有状态的服务来说是这是一种不可思议的强力功能，因为你可以将这些探针附加在一个运行中的程序而不需重新编译它，并且几乎不会带来性能损失。这种思想诞生在[DTrace](http://dtrace.org/blogs/about/)，而后由`BPF`将这种观测能力
移植到`Linux`中。


但是`Go`在`1.17`之前的调用规约(`calling convention`)使得`Go`的追踪变得复杂。在[System V AMD64调用规约](https://en.wikipedia.org/wiki/X86_calling_conventions#System_V_AMD64_ABI)中，函数入参及返回值均通
寄存器传递。`BPF`的工具也假定编译器会遵循这一规约，但是`Go`没有。不同的是，`Go`遵循`Plan9`的调用规约，即通过栈来传递参数。返回值也会通过出栈来返回。


对于`uprobe`而言这意味着我们不能遵循AMD64调用规约，使用`arg`参数来将寄存器里的参数读出。与此相对应的是，我们需要从栈里将参数读出来。从栈里读参会比较繁琐，因为你需要获取栈帧(`stack pointer`)，从中读取参数地址，然后读取地址里
的参数。在`bpftrace-0.9.3`里，这些操作被封装成了[sargx](https://github.com/iovisor/bpftrace/issues/740)，所以还不算特别糟。


但是对于`uretprobe`就不一样了。不同于每个`goroutine`使用一个线程，`Go`的是多个`goroutine`对应多个线程的（"M:N调度"）。所以不同于每个线程拥有2MB的栈空间，每个goroutine只有被goroutine自己维护而非操作系统维护的，短短的
2KB的栈空间。当程序需要为一个`goroutine`增加栈空间并且当前空间内没有足够多的空余时，运行时会将整个`goroutine`的栈拷贝到另外一个有足够多空间用来扩展的内存空间中。


当你配置[uretprobe](https://github.com/torvalds/linux/blob/v5.8/kernel/events/uprobes.c#L1861-L1925)时，内核也会创建一个拥有返回探针处理的`uprobe`。当这个`uprobe`触发时，它会劫持返回地址并且使用一个中断
的“跳转地址”(tramponline)来替代它。


如果这个地址在`uprobe`触发时被移动了，返回地址将不再有效，所以一个`uretprobe`将会读取其他地方的内存。这将会使得程序崩溃。


为了解决这个问题，你需要从程序的入口处使用`uprobe`来追踪程序调用，然后记录函数每个`return`点的偏移信息。这显得格外的粗暴并且涉及二进制信息的反汇编。


你大概不会花费一整天来学习汇编，我当然也不会。所以让我们快速的来看下如何读取`go`反汇编后的内容。假设这是我们的程序：

``` 
package main

import (
	"fmt"
	"os"
)

func swap(x, y string) (string, string) {
	return y, x
}

func main() {
	args := os.Args
	if len(args) < 3 {
		panic("needs 2 args")
	}
	a, b := swap(args[1], args[2])
	fmt.Println(a, b)
}
```

由于这段程序比较简短，`Go`可能会把`swap`函数进行内联。为了能够说明问题，我们将会使用`go build -gcflags '-l' -o swapper .`进行编译以防止内联。


首先我们使用`GDB`来反汇编程序。你当然也可以使用`objdump`来进行，但是这里我们希望能够多获取些内容。

```
$ gdb --args ./swapper hello go
...
Reading symbols from ./swapper...
Loading Go Runtime support.
(gdb) b main.swap
Breakpoint 1 at 0x497800: file /home/tim/swapper/main.go, line 9
.
(gdb) run
Starting program: /home/tim/swapper/swapper hello world
[New LWP 3413956]
[New LWP 3413957]
[New LWP 3413958]
[New LWP 3413959]
[New LWP 3413960]

Thread 1 "swapper" hit Breakpoint 1, main.swap (x=..., y=..., ~r2=..., ~r3=...)
    at /home/tim/swapper/main.go:9
9               return y, x
(gdb) disas
Dump of assembler code for function main.swap:
=> 0x0000000000497800 <+0>:     mov    rax,QWORD PTR [rsp+0x18]
   0x0000000000497805 <+5>:     mov    QWORD PTR [rsp+0x28],rax
   0x000000000049780a <+10>:    mov    rax,QWORD PTR [rsp+0x20]
   0x000000000049780f <+15>:    mov    QWORD PTR [rsp+0x30],rax
   0x0000000000497814 <+20>:    mov    rax,QWORD PTR [rsp+0x8]
   0x0000000000497819 <+25>:    mov    QWORD PTR [rsp+0x38],rax
   0x000000000049781e <+30>:    mov    rax,QWORD PTR [rsp+0x10]
   0x0000000000497823 <+35>:    mov    QWORD PTR [rsp+0x40],rax
   0x0000000000497828 <+40>:    ret
End of assembler dump.
```

总的来看，我们有4个指针需要移动：每个`string`都有一个长度以及一段字节码，并且我们有两个`string`。函数将指针重新排列在栈上，并且当函数返回时，这些值会从栈上弹出。


第一个指令是将栈帧上偏移量为`0x18`的值移动到暂存寄存器`rax`。让我们查看下这个地址，然后看看它是否是一个可读的`string`：

```
(gdb) x/a $rsp+0x18
0xc00011af18:   0x7fffffffddcd
(gdb) x/s 0x7fffffffddcd
0x7fffffffddcd: "go"
```

妙啊！所以第一个指令的意思是，我们将值喜庆`string`的64-bit的指针(`QWORD PTR`)赋给了暂存寄存器。下一个指令是将同一个指针从暂存区移动到栈顶(rsp+0x28)。


下一个指令是将`0x20`上的任意值移动到暂存区。这是个整数：我们字符串的长度！

```
(gdb) x/a $rsp+0x20
0xc00011af20:   0x2
```

然后这个整数就被从暂存区移动到栈顶(rsp+0x30)。接下来的四个指令对另外两个参数做了相同的事情：

```
(gdb) x/a $rsp+0x8
0xc00011af08:   0x7fffffffddc7
(gdb) x/s 0x7fffffffddc7
0x7fffffffddc7: "hello"

(gdb) x/a $rsp+0x10
0xc00011af10:   0x5
```

我们单步执行(`si`)8次，直到来到`ret`指令处：

```
...
(gdb) si
0x0000000000497828 in main.swap (x=..., y=..., ~r2=..., ~r3=...)
    at /home/tim/swapper/main.go:9
9               return y, x
(gdb) disas
Dump of assembler code for function main.swap:
   0x0000000000497800 <+0>:     mov    rax,QWORD PTR [rsp+0x18]
   0x0000000000497805 <+5>:     mov    QWORD PTR [rsp+0x28],rax
   0x000000000049780a <+10>:    mov    rax,QWORD PTR [rsp+0x20]
   0x000000000049780f <+15>:    mov    QWORD PTR [rsp+0x30],rax
   0x0000000000497814 <+20>:    mov    rax,QWORD PTR [rsp+0x8]
   0x0000000000497819 <+25>:    mov    QWORD PTR [rsp+0x38],rax
   0x000000000049781e <+30>:    mov    rax,QWORD PTR [rsp+0x10]
   0x0000000000497823 <+35>:    mov    QWORD PTR [rsp+0x40],rax
=> 0x0000000000497828 <+40>:    ret
End of assembler dump.
```

函数已经完成了所有的功能，并且我们来到了这个函数将会返回给调用者的地方。现在我们可以确认下栈顶的内存地址：

```
(gdb) x/a $rsp+0x40
0xc00011af40:   0x5
(gdb) x/a $rsp+0x38
0xc00011af38:   0x7fffffffddc7
(gdb) x/s  0x7fffffffddc7
0x7fffffffddc7: "hello"
```

此时，我们可以看到我们已经将返回值移动到距离栈顶一定偏移量的指针上，而指针指向字符串。因为是在栈上，所以是“后进先出”的。这里可能会有些困惑因为函数的主要功能是交换这两个字符串。


如果你跟上了我的思路，自然的就能画出这样的分布：
![stack](stack.png)


如何将我们所学的内容应用到BPF呢？


首先，我们知道了尽管`Go`函数仅定义了两个参数，但实际上栈上有四个参数。所以我们需要定义两组栈上的参数。我们可以将它们正确的通过`bpftrace`里的`str`函数：`bpftrace:str(sarg0, sarg1)`来输出`x`，`str(sarg2, sarg3)`来
输出`y`。


然后，尽管`uretprobe`无法工作，我们可以通过添加一个指向`return`指令偏移量的`uprobe`来模拟它。如果你再看下汇编指令，就能看到这个偏移地址是`+40`。所以`uprobe`最终看起来
是：`uprobe:./bin/swapper:"main.swap"+40`。当我们触发这个探针时，我们仅查看返回值寄存器无法满足目标。我们需要检查上述发现的每个返回值的偏移地址。最终的`bpftrace`程序如下：

```
#!/usr/bin/env bpftrace

uprobe:./swapper:"main.swap"
{
    printf("swapping \"%s\" and \"%s\"\n",
        str(sarg0, sarg1), str(sarg2, sarg3));
}

uprobe:./swapper:"main.swap"+40
{
    printf("results: \"%s\" and \"%s\"\n",
        str(*(reg("sp")+0x28), *(reg("sp")+0x30)),
        str(*(reg("sp")+0x38), *(reg("sp")+0x40))
        )
}
```

我们在一个终端运行这段代码，在另一个终端运行`./swapper hello world`：

```
$ sudo ./swapper.bt
Attaching 2 probes...
swapping "hello" and "go"
results: "go" and "hello"
^C
```

如你所见，仅一个`return probe`就需要做很多的准备。如果我们的程序有很多的返回点，我们不得不为每个返回点都做一次相同的事情。


对于一些复杂的函数，如`Nomad`的`FSM` [Apply](https://github.com/hashicorp/nomad/blob/v1.1.4/nomad/fsm.go#L193-L322)方法，我不得不采用如下方式生成`bpftrace`代码的方法：

```
#!/usr/bin/env bash

cat <<EOF
#!/usr/bin/env bpftrace
/*
Get Nomad FSM.Apply latency
Note: using sarg with offsets isn't really concurrency safe and emits a warning
*/

EOF

base=$(objdump --disassemble="github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply" \
               -Mintel -S ./bin/nomad \
               | awk '/hashicorp/{print $1}' \
               | head -1)

objdump --disassemble="github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply" \
        -Mintel -S ./bin/nomad \
        | awk -F' |:' '/ret/{print $2}' \
        | xargs -I % \
        python3 -c "print('uprobe:./bin/nomad:\"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply\"+' + hex(0x% - 0x$base))
print('{')
print('  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);')
print('  delete(@start[str(*sarg1)]);')
print('}')
print('')
"
```

这样就得到了下面近300行的庞然大物：

```
#!/usr/bin/env bpftrace
/*
Get Nomad FSM.Apply latency
Note: using sarg with offsets isn't really concurrency safe and emits a warning
*/

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x1d3
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x257
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x2f3
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x377
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x3fb
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x49b
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x51b
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x5a0
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x634
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x6b4
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x738
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x7e7
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x86e
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x8ee
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x982
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0xa06
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0xa8e
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0xb27
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0xbae
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0xc2e
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0xcc2
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0xd46
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0xdce
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0xe77
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0xefb
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0xf80
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x1014
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x1098
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x111c
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x11b7
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x123b
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x12c0
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x1350
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x13d0
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x1450
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x14f7
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x1577
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x15f7
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x168f
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x170f
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x178f
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x18ca
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x1948
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x19ce
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x1a52
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x1a6d
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x1b07
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x1b87
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}

uprobe:./bin/nomad:"github.com/hashicorp/nomad/nomad.(*nomadFSM).Apply"+0x1c0e
{
  @usecs = hist((nsecs - @start[str(*sarg1)]) / 1000);
  delete(@start[str(*sarg1)]);
}
```


`Go 1.17`引入的新的调用规约使得这种情况得到改善，但是仍没有解决`uretprobe`的问题。相同的`swapper`代码在`Go 1.17`上将会反汇编成如下内容：

```
(gdb) disas
Dump of assembler code for function main.swap:
=> 0x000000000047e260 <+0>:     mov    QWORD PTR [rsp+0x8],rax
   0x000000000047e265 <+5>:     mov    QWORD PTR [rsp+0x18],rcx
   0x000000000047e26a <+10>:    mov    rdx,rax
   0x000000000047e26d <+13>:    mov    rax,rcx
   0x000000000047e270 <+16>:    mov    rsi,rbx
   0x000000000047e273 <+19>:    mov    rbx,rdi
   0x000000000047e276 <+22>:    mov    rcx,rdx
   0x000000000047e279 <+25>:    mov    rdi,rsi
   0x000000000047e27c <+28>:    ret
End of assembler dump.
```

所有的值传递操作都通过寄存器进行了，减少了指针寻址的内容：

```
(gdb) x/s $rax
0x7fffffffddca: "hello"
(gdb) i r $rbx
rbx            0x5                 5
(gdb) x/s $rcx
0x7fffffffddd0: "go"
(gdb) i r $rdi
rdi            0x2                 2
```

（我确实不知道为什么第二个参数的长度存储在`rdi`而非`rdx`，如果你知道的话，我很乐意知晓下）（译者按：参见[golang-1.17参数调用规约](https://liyan-ah.github.io/2023/03/03/golang-1-17-%E5%8F%82%E6%95%B0%E8%B0%83%E7%94%A8%E8%A7%84%E7%BA%A6/#more)）。


返回值也放到了寄存器里，这意味着我们可以通过`uretprobe`来直接获取。我们的`bpftrace`程序变得简洁了许多：

```
#!/usr/bin/env bpftrace

uprobe:./swapper:"main.swap"
{
    printf("swapping \"%s\" and \"%s\"\n",
      str(reg("ax")), str(reg("cx")));
}

uretprobe:./swapper:"main.swap"
{
    printf("results: \"%s\" and \"%s\"\n",
      str(reg("ax")), str(reg("cx")));
}
$ sudo ./swapper.bt
Attaching 2 probes...
swapping "hello" and "go"
results: "go" and "hello"
^C
```


所以问题是什么？这样不是很好么？目前为止，我们关注的示例都没有需要很多栈空间以至于运行时需要对栈进行调整。而运行时的调整是`uretprobe`失败的原因。  


看下下面的示例。`temp`变量从没有逃逸到对上（我们可以通过添加`-gcflags -m`进行编译以验证这一点），所以我们需要在`goroutine`栈上申请`sizeof(Example)*count`大小的空间。如果我们执行`./stacker 1000000`，将会申请
多余能够提供的空闲内存，`Go`的运行时将不得不移动栈空间。


```
package main

import (
	"fmt"
	"os"
	"strconv"
)

type Example struct {
	ID   int
	Name string
}

func stacker(count int) string {
	var result int
	for i := 0; i < count; i++ {
		temp := Example{ID: i * 2, Name: fmt.Sprintf("%d", result)}
		result += temp.ID
	}
	s := fmt.Sprintf("hello: %d", result)
	return s
}

func main() {
	args := os.Args
	if len(args) < 2 {
		panic("needs 1 arg")
	}
	count, err := strconv.Atoi(args[1])
	if err != nil {
		panic("arg needs to be a number")
	}

	s := stacker(count)
	fmt.Println(s)
}
```

这是我们的`bpftrace`程序：

```
#!/usr/bin/env bpftrace

uretprobe:./stacker:"main.stacker"
{
    printf("result: \"%s\"\n", str(reg("ax")));
}
```

如果我们在`uretprobe`加载的同时，给`stacker`一个巨大的参数`count`，程序将会崩溃！

```
$ ./stacker 1000000
runtime: unexpected return pc for main.stacker called from 0x7fffffffe000
stack: frame={sp:0xc000074ef0, fp:0xc000074f48} stack=[0xc000074000,0xc000075000)
...
```


这里是崩溃时完整的信息：

```
$ ./stacker 1000000
runtime: unexpected return pc for main.stacker called from 0x7fffffffe000
stack: frame={sp:0xc000074ef0, fp:0xc000074f48} stack=[0xc000074000,0xc000075000)
0x000000c000074df0:  0x0000000000000002  0x000000c000508100
0x000000c000074e00:  0x000000c000508000  0x00000000004672e0 <sync.(*Pool).pinSlow·dwrap·3+0x0000000000000000>
0x000000c000074e10:  0x0000000000557f58  0x000000c000074e08
0x000000c000074e20:  0x0000000000419860 <runtime.gcAssistAlloc.func1+0x0000000000000000>  0x000000c0000001a0
0x000000c000074e30:  0x0000000000010000  0x000000c000074eb8
0x000000c000074e40:  0x000000000040b305 <runtime.mallocgc+0x0000000000000125>  0x000000c0000001a0
0x000000c000074e50:  0x0000000000000002  0x000000c000074e88
0x000000c000074e60:  0x000000c000074e88  0x000000000047a06a <fmt.(*pp).free+0x00000000000000ca>
0x000000c000074e70:  0x0000000000522100  0x00000000004938e0
0x000000c000074e80:  0x000000c00007a820  0x000000c000074ee0
0x000000c000074e90:  0x000000000047a245 <fmt.Sprintf+0x0000000000000085>  0x000000c00007a820
0x000000c000074ea0:  0x000000c00012b230  0x000000000000000b
0x000000c000074eb0:  0x000000c0000001a0  0x000000c000074ee0
0x000000c000074ec0:  0x00000000004095e5 <runtime.convT64+0x0000000000000045>  0x0000000000000008
0x000000c000074ed0:  0x0000000000487ee0  0x000000c00007a800
0x000000c000074ee0:  0x000000c000074f38  0x0000000000480d7b <main.stacker+0x000000000000003b>
0x000000c000074ef0: <0x0000000644e0732a  0x0000000000000002
0x000000c000074f00:  0x000000c000074f28  0x0000000000000001
0x000000c000074f10:  0x0000000000000001  0x0000000644e0732a
0x000000c000074f20:  0x00000000000280fa  0x0000000000000000
0x000000c000074f30:  0x0000000000000000  0x000000c000074f70
0x000000c000074f40: !0x00007fffffffe000 >0x00000000000f4240
0x000000c000074f50:  0x0000000000000007  0x0000000000415d45 <runtime.gcenable+0x0000000000000085>
0x000000c000074f60:  0x00000000004873a0  0x000000c0000001a0
0x000000c000074f70:  0x000000c000074fd0  0x0000000000432047 <runtime.main+0x0000000000000227>
0x000000c000074f80:  0x000000c000022060  0x0000000000000000
0x000000c000074f90:  0x0000000000000000  0x0000000000000000
0x000000c000074fa0:  0x0100000000000000  0x0000000000000000
0x000000c000074fb0:  0x000000c0000001a0  0x0000000000432180 <runtime.main.func2+0x0000000000000000>
0x000000c000074fc0:  0x000000c000074fa6  0x000000c000074fb8
0x000000c000074fd0:  0x0000000000000000  0x000000000045ab01 <runtime.goexit+0x0000000000000001>
0x000000c000074fe0:  0x0000000000000000  0x0000000000000000
0x000000c000074ff0:  0x0000000000000000  0x0000000000000000
fatal error: unknown caller pc

runtime stack:
runtime.throw({0x4988ba, 0x516760})
        /usr/local/go/src/runtime/panic.go:1198 +0x71
runtime.gentraceback(0x400, 0x400, 0x80, 0x7f73bbffafff, 0x0, 0x0, 0x7fffffff, 0x7ffc46fe0e28, 0x7f73bbe23200, 0x0)
        /usr/local/go/src/runtime/traceback.go:274 +0x1956
runtime.scanstack(0xc0000001a0, 0xc000030698)
        /usr/local/go/src/runtime/mgcmark.go:748 +0x197
runtime.markroot.func1()
        /usr/local/go/src/runtime/mgcmark.go:232 +0xb1
runtime.markroot(0xc000030698, 0x14)
        /usr/local/go/src/runtime/mgcmark.go:205 +0x170
runtime.gcDrainN(0xc000030698, 0x10000)
        /usr/local/go/src/runtime/mgcmark.go:1134 +0x14b
runtime.gcAssistAlloc1(0xc0000001a0, 0xc000074b58)
        /usr/local/go/src/runtime/mgcmark.go:537 +0xef
runtime.gcAssistAlloc.func1()
        /usr/local/go/src/runtime/mgcmark.go:448 +0x25
runtime.systemstack()
        /usr/local/go/src/runtime/asm_amd64.s:383 +0x49

goroutine 1 [GC assist marking (scan)]:
runtime.systemstack_switch()
        /usr/local/go/src/runtime/asm_amd64.s:350 fp=0xc000074de8 sp=0xc000074de0 pc=0x458a20
runtime.gcAssistAlloc(0xc0000001a0)
        /usr/local/go/src/runtime/mgcmark.go:447 +0x18b fp=0xc000074e48 sp=0xc000074de8 pc=0x41974b
runtime.mallocgc(0x8, 0x487ee0, 0x0)
        /usr/local/go/src/runtime/malloc.go:959 +0x125 fp=0xc000074ec8 sp=0xc000074e48 pc=0x40b305
runtime.convT64(0x644e0732a)
        /usr/local/go/src/runtime/iface.go:364 +0x45 fp=0xc000074ef0 sp=0xc000074ec8 pc=0x4095e5
runtime: unexpected return pc for main.stacker called from 0x7fffffffe000
stack: frame={sp:0xc000074ef0, fp:0xc000074f48} stack=[0xc000074000,0xc000075000)
0x000000c000074df0:  0x0000000000000002  0x000000c000508100
0x000000c000074e00:  0x000000c000508000  0x00000000004672e0 <sync.(*Pool).pinSlow·dwrap·3+0x0000000000000000>
0x000000c000074e10:  0x0000000000557f58  0x000000c000074e08
0x000000c000074e20:  0x0000000000419860 <runtime.gcAssistAlloc.func1+0x0000000000000000>  0x000000c0000001a0
0x000000c000074e30:  0x0000000000010000  0x000000c000074eb8
0x000000c000074e40:  0x000000000040b305 <runtime.mallocgc+0x0000000000000125>  0x000000c0000001a0
0x000000c000074e50:  0x0000000000000002  0x000000c000074e88
0x000000c000074e60:  0x000000c000074e88  0x000000000047a06a <fmt.(*pp).free+0x00000000000000ca>
0x000000c000074e70:  0x0000000000522100  0x00000000004938e0
0x000000c000074e80:  0x000000c00007a820  0x000000c000074ee0
0x000000c000074e90:  0x000000000047a245 <fmt.Sprintf+0x0000000000000085>  0x000000c00007a820
0x000000c000074ea0:  0x000000c00012b230  0x000000000000000b
0x000000c000074eb0:  0x000000c0000001a0  0x000000c000074ee0
0x000000c000074ec0:  0x00000000004095e5 <runtime.convT64+0x0000000000000045>  0x0000000000000008
0x000000c000074ed0:  0x0000000000487ee0  0x000000c00007a800
0x000000c000074ee0:  0x000000c000074f38  0x0000000000480d7b <main.stacker+0x000000000000003b>
0x000000c000074ef0: <0x0000000644e0732a  0x0000000000000002
0x000000c000074f00:  0x000000c000074f28  0x0000000000000001
0x000000c000074f10:  0x0000000000000001  0x0000000644e0732a
0x000000c000074f20:  0x00000000000280fa  0x0000000000000000
0x000000c000074f30:  0x0000000000000000  0x000000c000074f70
0x000000c000074f40: !0x00007fffffffe000 >0x00000000000f4240
0x000000c000074f50:  0x0000000000000007  0x0000000000415d45 <runtime.gcenable+0x0000000000000085>
0x000000c000074f60:  0x00000000004873a0  0x000000c0000001a0
0x000000c000074f70:  0x000000c000074fd0  0x0000000000432047 <runtime.main+0x0000000000000227>
0x000000c000074f80:  0x000000c000022060  0x0000000000000000
0x000000c000074f90:  0x0000000000000000  0x0000000000000000
0x000000c000074fa0:  0x0100000000000000  0x0000000000000000
0x000000c000074fb0:  0x000000c0000001a0  0x0000000000432180 <runtime.main.func2+0x0000000000000000>
0x000000c000074fc0:  0x000000c000074fa6  0x000000c000074fb8
0x000000c000074fd0:  0x0000000000000000  0x000000000045ab01 <runtime.goexit+0x0000000000000001>
0x000000c000074fe0:  0x0000000000000000  0x0000000000000000
0x000000c000074ff0:  0x0000000000000000  0x0000000000000000
main.stacker(0xf4240)
        /home/tim/stacker/main.go:17 +0x3b fp=0xc000074f48 sp=0xc000074ef0 pc=0x480d7b
```


这样，我们仍然不得不使用之前实践的`uprobe+offset`的方式来进行`uretprobe`的实现。`bpftrace`程序会正常工作，但是地址的偏移量将很大程度上取决于使用的`Go`版本：

```
#!/usr/bin/env bpftrace

uprobe:./stacker:"main.stacker"+213
{
    printf("result: \"%s\"\n", str(reg("ax")));
}
```

这个问题看起来不会在`Go`的运行时侧修复，因为可重新分配的栈空间是整个`goroutine`内存模型的基础。但是通过`uprobe`以及一点小小的调整，你可以实现`uretprobe`的功能。
