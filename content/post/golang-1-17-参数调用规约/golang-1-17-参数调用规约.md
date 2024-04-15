---
title: go-1.17+ 调用规约
author: 李岩
tags:
  - golang
  - go-1.17
categories:
  - BPF
date: 2023-03-03 20:59:00
---
> `go-1.17`是一个很不友好的版本，这里我指的是函数调用规约的变更。在此之前，虽然栈传参比较奇怪，但是在掌握了规律后，参数信息很好获取。升级到`go-1.17`之后，笔者发现变更后的寄存器传值方式并不是系统的调用规约，至少和`C/C++`的是完全不一致的。这个问题使得笔者在处理`ebpf`方案时，始终无法覆盖`go-1.17+`的版本。虽然短期不会造成影响，线上服务使用的大多还在`go-1.16`以下，但是这始终是一个绕不过去的问题。近期通过查阅资料和参考其他开源项目里对这部分内容的处理，整理了一下`go-1.17+`的调用规约。

`go`在`1.17`之前使用的是内存栈来传递参数，这种传参的方式使得`golang`的语言设计很灵活：`golang`函数的多返回值能够很容易的实现。同样的，由于`golang`需要这样灵活的能力，是的系统默认的调用规约方式并不适用。在[Proposal: Register-based Go calling convention](https://go.googlesource.com/proposal/+/refs/changes/78/248178/1/design/40724-register-calling.md)文章里对这个问题进行了详细的讨论，总结起来是`golang`的特性使得使用系统默认规约并不能带来多语言交互上的收益，且`golang`希望保持独特。  
本文下面会给出总结的调用规约，并且给出验证程序。本文档的整理所基于的平台是`x86_64`的`centos8`系统。其他架构下，寄存器名称可能不同。
<!--more-->

# 调用规约
入参：  

| 参数序号 | 标准规约 | golang规约 |
| -       | -     | -  	       |
| 1	      |  rdi  | rax |
| 2	      | rsi | rbx |
| 3       | rdx | rcx | 
| 4       | rcx | rdi |
| 5       | r8 | rsi |
| 6       | r9  | r8 |
| 7       | 栈传值 | r9 |
| 8       | 栈传值 | r10 |
| 9       | 栈传值 | r11 |
| 10      | 栈传值 | 栈传值 |

返回值：

| 参数序号 | 标准规约 | golang规约 |
| -       | -     | -  	       |
| 1	      |  rax  | rax |
| 2	      | - | rbx |
| 3 | - | rcx | 
| 4 | - | rdi |
| 5 | - | rsi |
| 6 | -  | r8 |
| 7 | - | r9 |
| 8 | - | r10 |
| 9 | - | r11 |
| 10 | - | 栈传值 |

# 验证规约
这个条件是比较好验证的，看下验证代码:
``` golang
// go version 1.18
// ./go_18/arg/main.go
package main

import "fmt"

//go:noinline
func longArgs(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11 uint64) (r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11 uint64) {

	return a1 + 1, a2 + 2, a3 + 3, a4 + 4, a5 + 5, a6 + 6, a7 + 7, a8 + 8, a9 + 9, a10 + 10, a11 + 11
}

func main() {
	a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11 := longArgs(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)
	fmt.Println(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11)
}
```

先生成`plan9`代码以说明参数传入和参数返回均是使用的寄存器，并且寄存器顺序是一致的（内存传参时也是）。

``` golang
go build -gcflags "-N -S -l" >> arg.info
# 然后截取部分生成 plan9 汇编
# go_18/arg
"".longArgs STEXT nosplit size=411 args=0x68 locals=0x50 funcid=0x0 align=0x0
	0x0000 00000 	TEXT	"".longArgs(SB), NOSPLIT|ABIInternal, $80-104
	0x0000 00000 	SUBQ	$80, SP
	0x0004 00004 	MOVQ	BP, 72(SP)
	0x0009 00009 	LEAQ	72(SP), BP
	0x000e 00014 	FUNCDATA	$0, gclocals·33cdeccccebe80329f1fdbee7f5874cb(SB)
	0x000e 00014 	FUNCDATA	$1, gclocals·33cdeccccebe80329f1fdbee7f5874cb(SB)
	0x000e 00014 	FUNCDATA	$5, "".longArgs.arginfo1(SB)
	0x000e 00014 	MOVQ	AX, "".a1+120(SP)  # 注意这里的读取参数寄存器
	0x0013 00019 	MOVQ	BX, "".a2+128(SP)
	0x001b 00027 	MOVQ	CX, "".a3+136(SP)
	0x0023 00035 	MOVQ	DI, "".a4+144(SP)
	0x002b 00043 	MOVQ	SI, "".a5+152(SP)
	0x0033 00051 	MOVQ	R8, "".a6+160(SP)
	0x003b 00059 	MOVQ	R9, "".a7+168(SP)
	0x0043 00067 	MOVQ	R10, "".a8+176(SP)
	0x004b 00075 	MOVQ	R11, "".a9+184(SP)
	0x0053 00083 	MOVQ	$0, "".r1+64(SP)
	0x005c 00092 	MOVQ	$0, "".r2+56(SP)
	0x0065 00101 	MOVQ	$0, "".r3+48(SP)
	0x006e 00110 	MOVQ	$0, "".r4+40(SP)
	0x0077 00119 	MOVQ	$0, "".r5+32(SP)
	0x0080 00128 	MOVQ	$0, "".r6+24(SP)
	0x0089 00137 	MOVQ	$0, "".r7+16(SP)
	0x0092 00146 	MOVQ	$0, "".r8+8(SP)
	0x009b 00155 	MOVQ	$0, "".r9(SP)
	0x00a3 00163 	MOVQ	$0, "".r10+104(SP)
	0x00ac 00172 	MOVQ	$0, "".r11+112(SP)
	0x00b5 00181 	MOVQ	"".a1+120(SP), DX
	0x00ba 00186 	INCQ	DX
	0x00bd 00189 	MOVQ	DX, "".r1+64(SP)
	0x00c2 00194 	MOVQ	"".a2+128(SP), DX
	0x00ca 00202 	ADDQ	$2, DX
	0x00ce 00206 	MOVQ	DX, "".r2+56(SP)
	0x00d3 00211 	MOVQ	"".a3+136(SP), DX
	0x00db 00219 	ADDQ	$3, DX
	0x00df 00223 	MOVQ	DX, "".r3+48(SP)
	0x00e4 00228 	MOVQ	"".a4+144(SP), DX
	0x00ec 00236 	ADDQ	$4, DX
	0x00f0 00240 	MOVQ	DX, "".r4+40(SP)
	0x00f5 00245 	MOVQ	"".a5+152(SP), DX
	0x00fd 00253 	ADDQ	$5, DX
	0x0101 00257 	MOVQ	DX, "".r5+32(SP)
	0x0106 00262 	MOVQ	"".a6+160(SP), DX
	0x010e 00270 	ADDQ	$6, DX
	0x0112 00274 	MOVQ	DX, "".r6+24(SP)
	0x0117 00279 	MOVQ	"".a7+168(SP), DX
	0x011f 00287 	ADDQ	$7, DX
	0x0123 00291 	MOVQ	DX, "".r7+16(SP)
	0x0128 00296 	MOVQ	"".a8+176(SP), DX
	0x0130 00304 	ADDQ	$8, DX
	0x0134 00308 	MOVQ	DX, "".r8+8(SP)
	0x0139 00313 	MOVQ	"".a9+184(SP), DX
	0x0141 00321 	ADDQ	$9, DX
	0x0145 00325 	MOVQ	DX, "".r9(SP)
	0x0149 00329 	MOVQ	"".a10+88(SP), DX   # 这里使用栈传递a10
	0x014e 00334 	ADDQ	$10, DX
	0x0152 00338 	MOVQ	DX, "".r10+104(SP)
	0x0157 00343 	MOVQ	"".a11+96(SP), DX
	0x015c 00348 	ADDQ	$11, DX
	0x0160 00352 	MOVQ	DX, "".r11+112(SP)  # 这里使用栈传递 a11
	0x0165 00357 	MOVQ	"".r1+64(SP), AX    # 注意这里返回参数的寄存器
	0x016a 00362 	MOVQ	"".r2+56(SP), BX
	0x016f 00367 	MOVQ	"".r3+48(SP), CX
	0x0174 00372 	MOVQ	"".r4+40(SP), DI
	0x0179 00377 	MOVQ	"".r5+32(SP), SI
	0x017e 00382 	MOVQ	"".r6+24(SP), R8
	0x0183 00387 	MOVQ	"".r7+16(SP), R9
	0x0188 00392 	MOVQ	"".r8+8(SP), R10
	0x018d 00397 	MOVQ	"".r9(SP), R11
	0x0191 00401 	MOVQ	72(SP), BP
	0x0196 00406 	ADDQ	$80, SP
	0x019a 00410 	RET
```

从上面的`plan9`可以看出来，函数入参和返回值确实是使用寄存器传递的，且寄存器信息是一致的。实际上到这里就足够了。但是笔者还需要确定下使用的寄存器名称并进行验证，因为这些参数是在做`ebpf`逻辑处理的时候使用的。

# 使用ebpf获取入参并输出

```  
// 这里表述下依据plan9寄存器符号推测的实际寄存器名称：
#define GO_PARAM1(x) ((x)->rax)
#define GO_PARAM2(x) ((x)->rbx)
#define GO_PARAM3(x) ((x)->rcx)
#define GO_PARAM4(x) ((x)->rdi)
#define GO_PARAM5(x) ((x)->rsi)
#define GO_PARAM6(x) ((x)->r8)
#define GO_PARAM7(x) ((x)->r9)
#define GO_PARAM8(x) ((x)->r10)
#define GO_PARAM9(x) ((x)->r11)

struct event {
    u32 pid;
    u8 comm[64];

    // args
    u64 arg0;
    u64 arg1;
    u64 arg2;
    u64 arg3;
    u64 arg4;
    u64 arg5;
    u64 arg6;
    u64 arg7;
    u64 arg8;
    u64 arg9;
    u64 arg10;
};
SEC("uprobe/main.longArgs")
int uprobe__main_long_args(struct pt_regs *ctx) {
    struct event args={};
    args.pid = bpf_get_current_pid_tgid();
    bpf_get_current_comm(&args.comm, sizeof(args.comm));


    // read args 0-8，从寄存器中获取
    args.arg0 = GO_PARAM1(ctx);
    args.arg1 = GO_PARAM2(ctx);
    args.arg2 = GO_PARAM3(ctx);
    args.arg3 = GO_PARAM4(ctx);
    args.arg4 = GO_PARAM5(ctx);
    args.arg5 = GO_PARAM6(ctx);
    args.arg6 = GO_PARAM7(ctx);
    args.arg7 = GO_PARAM8(ctx);
    args.arg8 = GO_PARAM9(ctx);
    
    // read args 9-10，从栈上获取
    bpf_probe_read(&args.arg9, sizeof(args.arg9), (void*)(PT_REGS_SP(ctx))+8);
    bpf_probe_read(&args.arg10, sizeof(args.arg10), (void*)(PT_REGS_SP(ctx))+16);

    bpf_perf_event_output(ctx, &events, BPF_F_CURRENT_CPU, &args, sizeof(args));
    return 0;
}
```
编译完成后，启动这部分`ebpf`监听任务：

``` 
# 启动监听
./go_18 -bin_path ./arg/arg -uprobe main.longArgs
2023/03/03 22:07:32 Listening for events..
# 触发 ./arg/arg 执行
2023/03/03 22:07:46 pid: 756309, comm: arg
2023/03/03 22:07:46 /home/odin/pdliyan/blog/go_18/arg/arg: main.longArgs  value: {Pid:756309 Comm:[97 114 103 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0] _:[0 0 0 0] Arg0:1 Arg1:2 Arg2:3 Arg3:4 Arg4:5 Arg5:6 Arg6:7 Arg7:8 Arg8:9 Arg9:10 Arg10:11}
# 请注意这里的参数是和我们的代码一致的。
2023/03/03 22:07:46 event info: {Pid:756309 Comm:[97 114 103 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0] _:[0 0 0 0] Arg0:1 Arg1:2 Arg2:3 Arg3:4 Arg4:5 Arg5:6 Arg6:7 Arg7:8 Arg8:9 Arg9:10 Arg10:11}
# 退出
2023/03/03 22:08:38 Received signal, exiting program...
```  

从上面的输出可以确定`plan9`的寄存器符号和实际寄存器的对应关系是正确的。  

以上就验证了困扰笔者的`go-17+`参数调用规约的问题。可以看到，依旧十分的奇葩。  
周末愉快。
