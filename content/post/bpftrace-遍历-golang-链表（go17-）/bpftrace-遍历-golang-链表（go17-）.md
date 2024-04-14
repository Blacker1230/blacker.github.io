---
title: bpftrace 遍历 golang 链表（go17+）
author: 李岩
tags:
  - bpftrace
  - bpf
categories:
  - 程序人生
date: 2023-11-18 15:36:00
---
> 不出意外的，之前提到的 ELF 文件解析内容又拖延了。目前还不知道什么时候有时间能够把希望完成的几篇文章给搞完。翻一翻目前的博客，已经有很久没有更新了。那就水一篇文章吧。目前算是项目里的低谷期，希望能够重拾程序员的意义。

在[bpftrace 无侵入遍历golang链表](https://liyan-ah.github.io/2022/07/22/cljb83dlm000ckcs6bp7thrf9/#more)里，笔者展示了使用`bpftrace`来遍历`golang`链表的方法。由于`go-17`和`go-16`的函数调用规约存在不同，因此[bpftrace 无侵入遍历golang链表](https://liyan-ah.github.io/2022/07/22/cljb83dlm000ckcs6bp7thrf9/#more)并不适用于`go-17`。其实这个问题在[go-1.17+ 调用规约](https://liyan-ah.github.io/2023/03/03/cljb83dm2001mkcs68hgf9o2s/#more)已经提到了解决方案。本文给一个实例，算是更进一步的延伸这个话题，希望能够起到一些效果。
<!--more-->

# 一、执行效果

```
$ sudo bpftrace ./link.bt
Attaching 1 probe...    // 在触发目标程序前，停止在这里
// 触发目标程序后，输出
== enter main.showNode
name: Alice, age: 11
name: Bob, age: 12
name: Claire, age: 13
== end

// 目标程序执行结果
$ ./link
name: Alice, age: 11
name: Bob, age: 12
name: Claire, age: 13
```

需要注意的是，笔者的验证环境为：
```
Linux 4.18.0-193.el8.x86_64
go version go1.17 linux/amd64
bpftrace v0.14.0-72-g6761-dirty
```
由于不同的`CPU`架构下，寄存器的信息会有所不同。本文中所涉及的代码示例仅在`amd64`里有效。

# 二、代码
本文涉及两部分代码：目标的`go`代码以及`bpftrace`代码。
```
// link/main.go
package main

import "fmt"

type Node struct {
	Name string
	Age  int64
	Next *Node
}

//go:noinline
func showNode(head *Node) {
	var cur = head
	for cur != nil {
		fmt.Printf("name: %s, age: %d
", cur.Name, cur.Age)
		cur = cur.Next
	}
	return
}

func main() {
	var node = &Node{
		Name: "Alice",
		Age:  11,
		Next: &Node{
			Name: "Bob",
			Age:  12,
			Next: &Node{
				Name: "Claire",
				Age:  13,
				Next: nil,
			},
		},
	}
	showNode(node)
}
```
`bpftrace`代码为：
```
// link/link.bt
// 这里，符号使用双引号包裹起来是个好习惯
uprobe:./link:"main.showNode"
{
  printf("== enter main.showNode
");
  $head_ptr = reg("ax");
  unroll(10){
    $name_ptr = *(uint64*)($head_ptr+0);
    $name_len = *(uint64*)($head_ptr+8);
    $age_v = *(int64*)($head_ptr+16);
    printf("name: %s, age: %d
", str($name_ptr, $name_len), $age_v);

    // set head = next
    $head_ptr = *(uint64*)($head_ptr+24);
    if ($head_ptr == 0){
        printf("== end
");
        return;
    }
  }
}
```

以上。周末愉快。
