---
title: centos 构建 local-k8s
author: 李岩
tags:
  - k8s
  - ebpf
categories:
  - 程序人生
  - code
date: 2022-02-24 17:27:00
---
> 工作原因，需要安装一个 local-k8s。中间碰了很多坑，做个记录。
环境：Linux test 4.18.0-193.el8.x86_64
<!--more-->
# kubectl
[kubectl安装说明](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)，可以直接使用包管理器安装，如：
```
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
sudo yum install -y kubectl
```
# minicube
[minicube安装说明](https://minikube.sigs.k8s.io/docs/start/) 也比较方便，官网里有不同系统的安装方式。笔者使用`curl`的安装：
```
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```
# start cluster
## 安装 kvm
[How to Install KVM on CentOS 8](https://phoenixnap.com/kb/install-kvm-centos) 
```
# check
cat /proc/cpuinfo | egrep "vmx|svm"
# install
sudo yum install @virt
# start

```
`minikube start --driver=<kvm2|hyperkit> --cni=flannel --cpus=4 --memory=8000 -p=<cluster-name>`，其中，笔者使用的`centos`系统使用`--driver=kvm2`选项。执行时存在诸多问题：

## kvm2 错误  
参照错误提示来。需要安装`libvirt`，笔者直接`sudo yum install libvirt`进行的。
## not in libvirt group
不确定为什么需要单独搞一个`libvirt group`，按照[issue-5617](https://github.com/kubernetes/minikube/issues/5617) 的说明，需要将用户添加到`libvirt`用户组中。笔者直接进行`sudo usermod -a -G libvirt ${USERNAME}`。
## virsh 报错
```
error: failed to connect to the hypervisor
error: authentication failed: access denied by policy
 ```
 需要在将当前用户添加到`libvirt`之后，需要配置`polkit`规则，确保`libvirt`组中的用户能够访问`libvirt`。
 ```
 # 方案参考 https://blog.csdn.net/cunjiu9486/article/details/109074019
 # /etc/polkit-1/rules.d/80-libvirt.rules
 polkit.addRule(function(action, subject){
	if (action.id == "org.libvirt.unix.manage" && subject.local && subject.active && subject.isInGroup("libvirt")){
		return polkit.Result.YES;
	}
});
 ```
 添加规则后，还需要重启 `polkitd`。简单粗暴：
 ```
 nohup /usr/lib/polkit-1/polkitd -r > /dev/null &
 ```
 ## Cannot find suitable emulator for x86_64
 通过 `sudo systemctl status libvirtd` 查看，发现报错是：`cannot initialize crypt`，继续安装`yum install libgcrypt`。
 ## dnsmasq: unknown user or group: dnsmasq
 ```
 groupadd dnsmasq
 useradd dnsmasq -g dnsmasq
 ```
 ## Failed to start host
 提示建议删除刚才的`cluster`，不清楚为啥，提示了就搞起来：
 ```
 minikube delete $cluster_name
 # 再次执行
 minikube start --driver=<kvm2|hyperkit> --cni=flannel --cpus=4 --memory=8000 -p=<cluster-name>
 ```
 这次可以了！
 ```
* Enabled addons: storage-provisioner, default-storageclass
* Done! kubectl is now configured to use "${cluster_name}" cluster and "default" namespace by default
```
