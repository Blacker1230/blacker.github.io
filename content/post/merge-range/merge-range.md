---
title: "合并区间"
description: 一个《合并区间》的问题及两种解法。
date: 2024-04-20T17:11:31+08:00
image: 
math: 
license: 
hidden: false
comments: true
draft: false
tags:
  - problem
  - rust
categories:
  - code
---

> 很久没有找工作的经历了，反而由于种种原因，最近接触了一些候选人。总体的感觉是最近是越来越卷了。
候选人的的水平明显比笔者毕业的时候高的多，也可能是笔者太菜了。其中一个合并区间的问题，笔者看到了
一个很有意思的解法。在这里记录下。

《合并区间》问题的思路很明显：排序、合并。笔者最近见到了一种特殊场景下很有意思的解法：在数据范围较小的情况下，使用桶的思想来
解决，就不再需要进行排序了。算法复杂度也从时间复杂度`o(nlgn)`降到了`o(n)`。这里记录下。

<!--more-->
## 题目描述
```
以数组 intervals 表示若干个区间的集合，其中单个区间为 intervals[i] = [starti, endi] 。请你合并所有重叠的区间，并返回 一个不重叠的区间数组，该数组需恰好覆盖输入中的所有区间 。

示例 1：
输入：intervals = [[1,3],[2,6],[8,10],[15,18]]
输出：[[1,6],[8,10],[15,18]]
解释：区间 [1,3] 和 [2,6] 重叠, 将它们合并为 [1,6].

示例 2：
输入：intervals = [[1,4],[4,5]]
输出：[[1,5]]
解释：区间 [1,4] 和 [4,5] 可被视为重叠区间。

提示：
1 <= intervals.length <= 10000
intervals[i].length == 2
0 <= starti <= endi <= 10000
```

## 两种解法
### 排序
先排序，然后遍历、比较。关键点在于需要处理好比较时的边界条件。
```rust
impl Solution {
    pub fn merge(mut intervals: Vec<Vec<i32>>) -> Vec<Vec<i32>> {
        let mut merged = vec![];
        intervals.sort_by(|x, y| x[0].cmp(&y[0]));

        let mut interval = (None, None);
        for v in intervals.iter() {
            if interval.0.is_none() {
                interval.0 = Some(v[0]);
                interval.1 = Some(v[1]);
                continue;
            }

            // [0, 1] and [1, 2]
            if interval.1.is_some() && interval.1.unwrap() >= v[0] {
                if interval.1.unwrap() < v[1] {
                    interval.1 = Some(v[1]);
                }
                continue;
            }

            // [0, 1] and [2, 3]
            merged.push(vec![interval.0.unwrap(), interval.1.unwrap()]);
            interval.0 = Some(v[0]);
            interval.1 = Some(v[1]);
        }
        if interval.0.is_some() {
            merged.push(vec![interval.0.unwrap(), interval.1.unwrap()]);
        }

        merged
    }
}
```
### 桶处理
采用匹配的思路，借助桶来记录数组的各个区间。这个思路还需要在体会下。
```rust
impl Solution {
    pub fn merge(intervals: Vec<Vec<i32>>) -> Vec<Vec<i32>> {
        let mut merged = vec![];
        if intervals.len() == 0 {
            return merged;
        }

        // 0. 找出桶的范围。这一步可以去掉，直接设一个 10000 大小的桶。
        let mut max = 0;
        for iter in intervals.iter() {
            if max < iter[1] {
                max = iter[1];
            }
        }
        // 由于 rust 的枚举特性，这里就不需要使用两个 bucket 了。
        let mut bucket = vec![None; (max + 1) as usize];

        for iter in intervals.iter() {
            if bucket[iter[0] as usize].is_none() {
                bucket[iter[0] as usize] = Some(0);
            }
            if bucket[iter[1] as usize].is_none() {
                bucket[iter[1] as usize] = Some(0);
            }
            bucket[iter[0] as usize] = Some(bucket[iter[0] as usize].unwrap() + 1);
            bucket[iter[1] as usize] = Some(bucket[iter[1] as usize].unwrap() - 1);
        }

        let mut start = None;
        let mut sum = 0;
        let mut p = 0 as usize;
        loop {
            if p >= bucket.len() {
                break;
            }
            let iter = bucket[p];
            if iter.is_none() {
                p += 1;
                continue;
            }
            if start.is_none() {
                start = Some(p);
            }

            sum += iter.unwrap();
            if sum == 0 {
                merged.push(vec![start.unwrap() as i32, p as i32]);
                start = None;
            }
            p += 1;
        }

        merged
    }
}
```

## 后记
这个问题是`leetcode`上的[56. 合并区间](https://leetcode.cn/problems/merge-intervals/description/)。一般刷题
的人都会刷到。惭愧的是笔者已经没有印象了。得赶紧把插件修一修，有时间刷点题。
