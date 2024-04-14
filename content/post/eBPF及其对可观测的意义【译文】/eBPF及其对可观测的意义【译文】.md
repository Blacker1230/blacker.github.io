---
title: eBPF及其对可观测的意义【译文】
author: 李岩
tags:
  - eBPF
  - 翻译
categories:
  - 程序人生
date: 2022-03-02 16:34:00
---
> 最近在做 eBPF 的技术调研。看到很多对 eBPF 的介绍。为了加强对内容的理解，笔者选择了其中的一篇尝试翻译。本着便于笔者自己理解的角度，很多内容加入了自己的一些理解，因此并不能算是严格意义上的“翻译”。文章涉及了 eBPF 的介绍、优势、不足，算是一篇 eBPF 的很好的介绍。现在把它贴上来，算是纪念自己的第一篇“译文”。  
原文地址：[What Is eBPF and Why Does It Matter for Observability?](https://newrelic.com/blog/best-practices/what-is-ebpf)

<!--more-->

# eBPF 及其对可观测领域的影响
当实现安全性、网络化以及可观测的特性时，在linux 内核中工作是非常理想化的。然而，它并非缺少挑战。无论是变更内核源码或者新增
内核模块，开发者通常会面对复杂的架构及难以调试的抽象层。[扩展的 BPF(eBPF)](https://www.kernel.org/doc/html/latest/bpf/index.html) 能够解决这两个问题。
伯克利包过滤器扩展技术(Extended Berkeley Packet Filter, eBPF) 是一种内核技术(自 Linux 4.x 引入)允许程序在无需变更内核源码或添加
额外的内核模块。你可以认为它是一种内核内置的轻量级的、沙箱式的虚拟机，编程人员可以通过 BPF 字节码来最大化的利用内核的资源。
使用 eBPF 消除了变更内核源码并且简化了软件利用现有层级的能力。因此，它是一种强大的技术，有可能从根本上改变网络、可观测性及安全
服务的工作方式。
这是一篇 eBPF 是什么、怎么工作以及什么时候考虑利用这种技术的文章。
# eBPF 是怎么工作的
eBPF 是事件驱动的，并且绑定到特定的代码路径。代码路径包含特殊的触发点(triggers)，或者称为钩子(hooks)。触发时，会执行所有绑定
到上面的 eBPF 程序。一些钩子的示例包括网络事件、系统调用、函数执行以及内核跟踪点。
当被触发时，代码会首先被编译成 BPF 字节码。然后，字节码会在执行前被校验，以确保不包含任何循环。校验会确保程序不会有意或无意的
破坏内核。
当代码在一个钩子上执行后，会产生辅助调用(helper calls)。这些辅助调用是一些eBPF访问内存的函数。辅助调用需要内核提前定义，目前
[调用的函数列表](https://man7.org/linux/man-pages/man7/bpf-helpers.7.html)仍在持续增长中。
eBPF 最开始的时候是作为一种增加过滤网络包时可观测性及安全性的工具。然而，时至今日，它已经成为一种用来让用户态的程序更加安全、
便捷、表现更好的工具。
# eBPF 的优势
eBPF 通常被用来进行[追踪](https://blog.px.dev/ebpf-function-tracing/)用户态的进程，这里列出一些它的优势：
* 高速、高效。eBPF 可以将网络包从内核态移动至用户态。而且，eBPF支持一个运行时（just-in-time, JIT）的编译器。在字节码被编译出来
后即可被执行，毋需基于平台重新解释；
* 低侵入性。当被用作调试器时，eBPF 无需停止服务便可以观测它的状态；
* 安全性。程序会被高效地加载到沙盒中，意味着内核源码被保护起来不会发生变更。执行时的校验能够确保资源不会由于程序陷入死循环而
阻塞；
* 便捷。相对于构建并维护内核的模块，编写内核的函数钩子要简单的多；
* 一致追踪。eBPF能够带来一个单一、有效、可用性强的追踪程序的框架。这增加了可视化及安全性；
* 可编程性。使用 eBPF 在不引入额外架构层的情况下，丰富了系统的特性。而且，由于代码是直接运行在内核里的，在不同的eBPF事件间存储
数据，而非像其他追踪程序一样转存出来，是可行的；
* 表达丰富。eBPF极具表达能力，这通常只能在其他高级语言中能够看到；
# eBPF 最佳实践
考虑到 eBPF 仍然是一项新的技术，很多使用仍待进一步开发。关于 eBPF 的最佳实践仍在随着这种技术的改进而不断增加。虽然没有已定义的
最佳实践存在，仍然有一些措施可以采纳以确保程序高效、便捷。
如果你在生态系统中使用了 eBPF，我们建议你：
* 使用 [LLVM Clang](https://clang.llvm.org) 来将 C 代码编辑为 eBPF 字节码。当 eBPF 刚出现时，编码及汇编均需要手动操作。然后，
开发者使用内核的汇编器生成字节码。幸运的是，现在已经不再需要这样操作了。Clang 为 C 语言编写的 eBPF 提供了前端及工具；
* 使用 BCC 工具集来编写 BPF 程序。[BPF 编译器集合（BPF Compiler Collection, BCC）](https://github.com/iovisor/bcc) 是一个帮助
构建高效内核追踪及管理程序的工具集。针对性能分析及网络拥塞控制相关的任务尤其合适。
# eBPF 的不足
尽管很强大，eBPF 并不是适合所有项目/生态系统的万金油。eBPF 有一些显而易见的不足，这些不足会让它在一些场景下不适用。一些开发者
可能会发现在如下场景下 eBPF 不适用：
* eBPF 限制在 Linux 系统及较新的内核版本。eBPF 是在 Linux 内核上发展并且完全聚焦在其上。这导致它相对于其他工具而言移植性不强。
此外，你需要一个相当新的内核。如果运行在任何早于 v4.13 的内核上，你将不能使用它。
* 沙盒编程是存在限制的。eBPF 通过限制应用程序可以接触的资源来提升安全性。然而，由于限制了操作系统的访问，功能上也被限制了。
# eBPF 适用哪些领域
eBPF [云原生应用](https://newrelic.com/solutions/cloud-adoption) 领域正迅速的获得关注。目前，eBPF 在以下两个场景中获得普遍
使用：
* 需要使用内核追踪实现可观测性。在这种场景下，eBPF 表现得更加快速、高效。这里不涉及到[上下文切换](https://www.quora.com/What-is-context-switching-in-Linux)，并且 eBPF 程序是事件驱动的所以毋需一个特定的触发器--所以你不会存在精度上的问题。
* 传统的安全监控不起作用。eBPF 在分布式及容器化的环境中有巨大的应用潜力，包括[Kubernets](https://kubernetes.io/blog/2017/12/using-ebpf-in-kubernetes/)。
在这些环境中，eBPF 可以缩小可见性的差距，因为他可以提供[HTTP 可见性追踪](https://blog.pixielabs.ai/ebpf-http-tracing/)。
在如下安全度量领域，你也可以发现 eBPF 被使用：
* 防火墙；
* 设备驱动；
* 网络性能监控；
# New Relic and eBPF
[Pixie](https://newrelic.com/platform/kubernetes-pixie) (acquired by New Relic), is an open source, kubernetes-native-in-cluster observability platform that provides instant visibility into Kubernetes workloads with no manual instrumentation. eBPF provides most of the magic behind the Pixie platform. As described earlier, eBPF allows you to run restricted code when an event is triggered. This event could be a function call either in kernel space(kprobes) or userspace(uprobes). Pixie uses both uprobes and kprobes to enable observability across services and applications.

Pixie automatically harvests telemetry data by leveraging eBPF, and its edge-machine intelligence connects this data with Kubernetes metadata to provide visibility while maintaining data locality. This visibility complements New Relic’s powerful Kubernetes observability solution. And starting in late May, you'll be able to send Pixie-generated telemetry data to New Relic One, gaining scalable retention, powerful visualizations, advanced correlation, and intelligent alerting capabilities.

# eBPF 正在可见的创造效率
eBPF 是一个提升 Linux 内核可观测、网络及安全性的新技术。它毋需变更内核源码或者添加新的模块，所以你可以在不引入复杂性的前提下，
提升系统的基础建设。
我们简要的谈到 eBPF 是什么、如何工作以及为什么它在分布式环境中如此有用。通过监控内核层，很多云上的可观测问题被解决了。你可以
享受数据中更深层次的可见性、更丰富的上下文以及更准确的信息。
