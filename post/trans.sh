#!/bin/bash

origin_path="/Users/liyan-work/zone/hexo-origin";
hugo_path="./";

posts=$(ls "${origin_path}/source/_posts/");

# 将 hexo 里的博文图片拷贝到 hugo 里。
cp "${origin_path}/source/images/*" "${hugo_path}/static/";
for post in ${posts[@]}; do
    echo ${post};
    name=${post//.md/};
    # 拷贝文件
    if [ ! -d "./${name}" ]; then
        mkdir "${hugo_path}/${name}";
        cp "${origin_path}/source/_posts/${post}" "${hugo_path}/${name}/";
    fi

    # 添加开始标志
    head=$(head -1 "${hugo_path}/${name}/${post}");
    if [ "${head}" != "---" ]; then
        echo ${name};
        content=$(cat "${hugo_path}/${name}/${post}");
        rm "${hugo_path}/${name}/${post}";
        echo "---" >> "${hugo_path}/${name}/${post}";
        echo "${content}" >> "${hugo_path}/${name}/${post}";
    fi

    # 处理图片
    # 注意，这里直接将`[/images/`删除了。
    # ![upload successful](/images/mindmap.png)
    # 会被修改为 
    # ![upload successful](mindmap.png)
    sed -i "" -e  "s#(/images/#(#g" "${hugo_path}/${name}/${post}";

done
