#!/bin/bash
echo -e "\033[1;34m[1. 当前分支与远程仓库]\033[0m"
git remote -v
echo ""
echo -e "\033[1;32m[2. 最近的提交历史图]\033[0m"
git log --graph --oneline --all -n 10 --decorate
echo ""
echo -e "\033[1;33m[3. 文件状态 (工作区 vs 暂存区)]\033[0m"
git status -s
