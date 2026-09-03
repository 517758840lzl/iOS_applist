# demolist：用 GitHub Actions 练 iOS 打包流程

演示仓库：`https://github.com/517758840lzl/iOS_applist`  
本地目录：`~/Desktop/demolist`（原生 iOS，不是 Flutter）

当前目标：**免费 Apple 账号也能跑通 CI 前半段**（checkout → xcodebuild 无签名 → 上传 Artifact）。

> 免费账号**不能**打正式可安装 IPA / 不能上架。完整签名版等有 $99 账号再加。

---

## 0. 远程

| 远程 | 地址 | 会不会跑 Actions |
| --- | --- | --- |
| `origin` | `git@github.com:517758840lzl/iOS_applist.git` | **会** |

这个 demo 的 `origin` 已经是 GitHub，推 `origin` 即可。

---

## 1. 我们现在在测什么

```
你点「Run workflow」
    → GitHub 分配临时 macOS
    → checkout 本仓库
    → xcodebuild Release（CODE_SIGNING_ALLOWED=NO）
    → 上传 demolist.app（无签名）为 Artifact
    → 机器销毁
```

| 能验证 | 不能验证（需 $99） |
| --- | --- |
| Actions 能否调度 macOS | Distribution 证书 / 描述文件 |
| 工程能否编过 | Archive / 正式 IPA |
| Artifact 上传下载 | 装到真机 / TestFlight / 上架 |

Workflow：`.github/workflows/ios-build-smoke.yml`（仅手动触发）。

---

## 2. 详细操作步骤

### Step 1 — 进入 demolist

```bash
cd ~/Desktop/demolist
git remote -v
git status
```

### Step 2 — 确认 CI 文件

- `.github/workflows/ios-build-smoke.yml`（**必须提交**）
- `.github/IOS_CI.md`（可选，说明用）

### Step 3 — 只提交 CI 文件

```bash
git add .github/workflows/ios-build-smoke.yml
# 可选：
# git add .github/IOS_CI.md

git commit -m "Add GitHub Actions iOS unsigned smoke build for CI practice."
git push origin HEAD
```

### Step 4 — 网页上手动跑

1. 打开：https://github.com/517758840lzl/iOS_applist/actions  
2. 左侧选 **iOS Build Smoke**  
3. **Run workflow** → 分支选 `main` → Run  

### Step 5 — 看结果

- 绿勾 = 冒烟成功  
- Artifacts 下载 `demolist-app-unsigned`（无签名，不能当正式安装包）

---

## 3. 成功标准

Actions 绿 + 能下到 Artifact = GitHub 打包流程已跑通。

---

## 4. 以后有 $99 账号时再做（预告）

导出证书与描述文件 → 配 Secrets → Archive / `xcodebuild -exportArchive` 出 IPA。

---

*演示项目：demolist（iOS_applist）；阶段：免费账号无签名冒烟。*
