---
title: TCP close 过程分析
author: 李岩
tags:
  - BPF
  - tcp
categories:
  - BPF
date: 2024-02-24 15:55:00
---
> 最近做了一些 TCP 连接观测相关的项目，又到了一个节奏点上了。这里趁着这个机会，做一些总结，同时描述一下 tcp close 过程中的一些疑惑。

在一些场景下，对服务的调用观测是很有价值的。笔者最近实践了使用`tcp_close`对服务主被调信息的观测，在这里作一下记录。
<!--more-->

# 一、tcp close 的一般过程
首先来看一下`tcp close`的过程。  
对`tcp`涉及操作的分析最权威的自然是RFC文档。依据[RFC-793](https://www.rfc-editor.org/rfc/pdfrfc/rfc793.txt.pdf)文档中的描述，`tcp close`时的状态转移信息为如下：

![tcp state](tcp-state.png)

但是涉及到具体的`Linux`下的`tcp close`的过程分析，文档就比较少了。笔者找到了一篇介绍`Linux`下`tcp`操作相关的介绍文档。[Analysis_TCP_in_Linux](https://github.com/fzyz999/Analysis_TCP_in_Linux/blob/master/tcp.pdf)中描述了主动触发`close`及被动触发`close`的`socket`双方涉及的函数调用，这为后面的验证提供了思路。

# 二、BPF 来观测 tcp close 过程
依据[Analysis_TCP_in_Linux](https://github.com/fzyz999/Analysis_TCP_in_Linux/blob/master/tcp.pdf)中的描述，笔者使用`python`构建了如下的验证`demo`。
```
# coding=UTF-8
import socket
import time
import getopt
import sys

srv_ip = ""
srv_port = 0

def server(srv_ip, srv_port):
    conn = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    conn.bind((srv_ip, srv_port))
    conn.listen(1024)
    conn.setblocking(1)
    index = 0

    while True:
        connection, address = conn.accept()
        try:
            dst = connection.getpeername()
            while True:
                request = connection.recv(1024)
                req_str = str(request.decode())
                if req_str == 'end':
                    # 这里以客户端传输一个特殊信息作为结束信息
                    # tcp server 和 client 之间的 close 是没有必然联系的
                    # 只能约定一个关闭条件。此时，无法确定客户端是否发起了断联
                    print("rcv end, close...")
                    connection.close()
                    time.sleep(2)
                    break
                # pass
                print("conn: %s:%d received: %s" % (dst[0], dst[1], req_str))
                response = ("client, msg index: %d" % index).encode()
                connection.send(response)
                index += 1
            print("conn: %s:%d closed" % (dst[0], dst[1]))
        except Exception as e:
            print("handle exception during dst. %s ..." % e)
        # pass
    # pass

def client(srv_ip, srv_port):
    try:
        server_addr = (srv_ip, srv_port)
        conn = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        conn.connect(server_addr)
        msg = ("server, msg index: 0").encode()
        conn.send(msg)
        data = conn.recv(1024)
        print("rcv from server: %s" % str(data.decode()))
        conn.send("end".encode())
        print("end. close ...")
        time.sleep(2)
        conn.close()
        time.sleep(2)
    except Exception as e:
        print("connection with server with error, %s" % e)
    return

if __name__ == "__main__":
    work_mode = "s"
    try:
        opts, args = getopt.getopt(sys.argv[1:], "i:p:s:c",
                                   ["srv_ip=", "port=", "server", "client"])
        if len(opts) == 0:
            print("unknown opts")
            sys.exit(0)
        for opt, arg in opts:
            if opt in ("-i", "--srv_ip"):
                srv_ip = arg
            if opt in ("-p", "--port"):
                srv_port = int(arg)
            if opt in ("--server"):
                work_mode = "s"
            if opt in ("--client"):
                work_mode = "c"
    except Exception as e:
        print("unknown args")
        sys.exit(0)

    if work_mode == "s":
        server(srv_ip, srv_port)
    else:
        client(srv_ip, srv_port)
```
从`demo`中可以看到，笔者构建的测试代码中，是`server`端发起的`close`，而后`client`端发起`close`。  
同时，笔者使用`bpftrace`构造了如下的观测代码：
```
#include <net/sock.h>

/*
TCP_ESTABLISHED = 1,
TCP_SYN_SENT = 2,
TCP_SYN_RECV = 3,
TCP_FIN_WAIT1 = 4,
TCP_FIN_WAIT2 = 5,
TCP_TIME_WAIT = 6,
TCP_CLOSE = 7,
TCP_CLOSE_WAIT = 8,
TCP_LAST_ACK = 9,
TCP_LISTEN = 10,
TCP_CLOSING = 11,
TCP_NEW_SYN_RECV = 12,
TCP_MAX_STATES = 13

每个 hook 点关注 进程的 pid, sk_state
*/

kprobe:tcp_close
/ comm == "python" /
{
  $sk = (struct sock*)arg0;
  printf("[tcp_close] pid: %d, state: %d, sock: %d, sk_max_ack_backlog: %d
",
                      pid, $sk->__sk_common.skc_state,
                      $sk, $sk->sk_max_ack_backlog);
}

kprobe:tcp_set_state
/ comm == "python" /
{
  $sk = (struct sock*)arg0;
  $ns = arg1;
  printf("[tcp_set_state] pid: %d, state: %d, ns: %d, sk: %d
",
                          pid, $sk->__sk_common.skc_state,
                          $ns, $sk);
}

kprobe:tcp_rcv_established
/ comm == "python" /
{
  $sk = (struct sock*)arg0;
  printf("[tcp_rcv_established] pid: %d, state: %d, sk: %d
",
                                pid, $sk->__sk_common.skc_state,
                                $sk);
}

kprobe:tcp_fin
/ comm == "python" /
{
  $sk = (struct sock*)arg0;
  printf("[tcp_fin] pid: %d, state: %d, sk: %d
",
                    pid, $sk->__sk_common.skc_state, $sk);
}

kprobe:tcp_send_fin
/ comm == "python" /
{
  $sk = (struct sock*)arg0;
  printf("[tcp_send_fin] pid: %d, state: %d, sk: %d
",
                         pid, $sk->__sk_common.skc_state, $sk);
}

kprobe:tcp_timewait_state_process
/ comm == "python" /
{
  $sk = (struct sock*)arg0;
  printf("[tcp_timewait_state_process] pid: %d, state: %d, sk: %d
",
                                       pid, $sk->__sk_common.skc_state,
                                       $sk);
}

kprobe:tcp_rcv_state_process
/ comm == "python" /
{
  $sk = (struct sock*)arg0;
  printf("[tcp_rcv_state_process] pid: %d, state: %d, sk: %d
",
                                       pid, $sk->__sk_common.skc_state,
                                       $sk);
}

kprobe:tcp_v4_do_rcv
/ comm == "python" /
{
  $sk = (struct sock*)arg0;
  printf("[tcp_v4_do_rcv] pid: %d, state: %d, sk: %d
",
                                       pid, $sk->__sk_common.skc_state,
                                       $sk);
}

kprobe:tcp_timewait_state_process
/ comm == "python" /
{
  $sk = (struct sock*)arg0;
  printf("[tcp_stream_wait_close] pid: %d, state: %d, sk: %d
",
                                       pid, $sk->__sk_common.skc_state,
                                       $sk);
}
```

首先启动`bpftrace`，然后启动`server`，使用`client`进行通信。此时`bpftrace`端的输出为：
```
[tcp_close] pid: 2828708, state: 1, sock: -1907214080, sk_max_ack_backlog: 1024
[tcp_set_state] pid: 2828708, state: 1, ns: 4, sk: -1907214080
[tcp_send_fin] pid: 2828708, state: 4, sk: -1907214080
[tcp_v4_do_rcv] pid: 2828708, state: 1, sk: -1907216512
[tcp_rcv_established] pid: 2828708, state: 1, sk: -1907216512
[tcp_fin] pid: 2828708, state: 1, sk: -1907216512
[tcp_set_state] pid: 2828708, state: 1, ns: 8, sk: -1907216512
[tcp_v4_do_rcv] pid: 2855763, state: 1, sk: -1907214080
[tcp_rcv_established] pid: 2855763, state: 1, sk: -1907214080
[tcp_close] pid: 2855763, state: 8, sock: -1907216512, sk_max_ack_backlog: 0
[tcp_set_state] pid: 2855763, state: 8, ns: 9, sk: -1907216512
[tcp_send_fin] pid: 2855763, state: 9, sk: -1907216512
[tcp_timewait_state_process] pid: 2855763, state: 6, sk: -2077492080
[tcp_stream_wait_close] pid: 2855763, state: 6, sk: -2077492080
[tcp_v4_do_rcv] pid: 2855763, state: 9, sk: -1907216512
[tcp_rcv_state_process] pid: 2855763, state: 9, sk: -1907216512
[tcp_set_state] pid: 2855763, state: 9, ns: 7, sk: -1907216512
```

# 三、笔者的困惑
这里，笔者观测到的结果和[Analysis_TCP_in_Linux](https://github.com/fzyz999/Analysis_TCP_in_Linux/blob/master/tcp.pdf)存在出入，主动发起`close`的一方，在第三次挥手时，响应的并不是`tcp_rcv_state_process`。相反的，被动`close`的`socket`在第四次挥手时触发了这个函数。而且，主动`close`的`socket`，第二次挥手时，响应的`socket`看起来发生了变更，而且其状态是`TCP_ESTABLISHED`。这其中需要继续探索。

以上，作为记录了部分总结。
