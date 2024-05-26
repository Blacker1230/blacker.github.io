---
title: "3-sum 问题"
description: 从面试开始说起...
date: 2024-05-26T14:39:35+08:00
hidden: false
comments: true
categories:
    - code
tags:
    - leetcode
---

## 从 3-sum 问题开始说起
[3-sum](https://leetcode.cn/problems/3sum/description/) 问题是 leetcode 中的一个经典问题。笔者最近重新重新回顾了这个问题，尴尬的是
关键时刻居然没有解出来。今天来重新回顾下。作为数组类问题中的经典问题，笔者认为这里有三个关键点：
1. 记得排序。数组问题大多需要进行排序，有序的数组才具有可操作性。
2. 通过比较，来决定下标移动的位置。在处理 2-sum 过程时，比较当前下标数字的和与目标值的大小来决定下标的下一步移动方向。
3. 对去重的处理。尴尬的就是这部分的处理过程。以笔者目前写代码的习惯，会直接使用 set 来进行去重。翻了下代码，对这部分的处理确实有点绕。

围绕第三点，下面给出两个解法。

### set 去重
先看第一种解法，在处理结果集不重复时，使用 HashSet 来处理结果集唯一性的问题：
``` Rust
impl Solution {
    pub fn three_sum_n(mut nums: Vec<i32>, sum: i32) -> Vec<Vec<i32>> {
        nums.sort();
        let mut res = std::collections::HashSet::new();
        for i in 0..nums.len() {
            let target = sum - nums[i];
            let mut left = i + 1;
            let mut right = nums.len() - 1;
            while left < right {
                if nums[left] + nums[right] == target {
                    // 题目中要求的时结果集不重复。直接使用 set 来保证唯一性。
                    res.insert(vec![nums[i], nums[left], nums[right]]);
                    // 找到一个后，同时移动 left & right 后继续遍历
                    left += 1;
                    right -= 1;
                    continue;
                }
                if nums[left] + nums[right] > target {
                    right -= 1;
                } else {
                    left += 1;
                }
            }
        }

        res.into_iter().collect()
    }

    pub fn three_sum(mut nums: Vec<i32>) -> Vec<Vec<i32>> {
        Self::three_sum_n(nums, 0)
    }
}
```

### 通过比较来去重
第二种解法也是经典解法：在移动下标时，确保当前值和前一个值不同。笔
者回顾了下自己的思路以及给候选人的建议：先进行去重，然后进行比对。
先去重的问题就是，像 [0, 0, 0] 这样的结果就会先被去重环节排除
掉。而题目中没有结果集中的 [x, y, z] x != y && y != z 的条件。
正确的去重方式应该是，通过后置位和前置位的对比来允许 [0, 0, 0]的
候选集能够出现。解题过程如下：

```Rust
impl Solution {
    pub fn three_sum_n(mut nums: Vec<i32>, sum: i32) -> Vec<Vec<i32>> {
        nums.sort();
        let mut res = vec![];
        for i in 0..nums.len() {
            // 同样需要对 i 进行去重处理
            if i != 0 && nums[i] == nums[i-1]{
                continue;
            }
            let target = sum - nums[i];
            let mut left = i + 1;
            let mut right = nums.len() - 1;
            while left < right {
                // 允许第一个 left 值继续处理。第二个值和前置值对比
                if left != i + 1 && nums[left] == nums[left - 1] {
                    left += 1;
                    continue;
                }
                // 允许第一个 right 值继续处理。第二个值和前置值对比
                if right != nums.len() - 1 && nums[right] == nums[right + 1] {
                    right -= 1;
                    continue;
                }

                if nums[left] + nums[right] == target {
                    res.push(vec![nums[i], nums[left], nums[right]]);
                    // 找到一个后，同时移动 left & right 后继续遍历
                    left += 1;
                    right -= 1;
                    continue;
                }
                if nums[left] + nums[right] > target {
                    right -= 1;
                } else {
                    left += 1;
                }
            }
        }
        res
    }

    pub fn three_sum(mut nums: Vec<i32>) -> Vec<Vec<i32>> {
        Self::three_sum_n(nums, 0)
    }
}
```

## 一些感想
最近接触了很多实习生，感觉现在的实习生实力都很强。笔者找工作时，简历里的项目只有小学期的一个项目以及实验室里的一个项目，而且工程量都很小。现在
的候选人都可以在网上找一些开源项目的教程项目来学习了，而且给开源项目提 PR 的能力也很强。确实超过笔者很多。  
另一点感想是，学校所在的城市对学生的工程能力还是有影响的：北上的研究生工程实践都很多，而且普遍对工程涉及的一些项目（Redis, ES等）都有一些了解。
而非大厂所在城市的学校，研究生跟着导师做的项目普遍偏学术，而且对工程的了解要少很多。这确实是地利带来的影响，而且确实对候选人的面试有很大的影响。
还是应该通过适当的实习来接触行业。同样的，工作了也需要不断的提升自己的视野面。
