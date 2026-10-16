# Codex 额度精灵岛：大模型操作手册

本文给执行任务的大模型使用。目标是从干净的 macOS 环境构建、安装、验证并维护 `Codex 额度精灵岛`，而不泄露用户的 Codex、ChatGPT 或第三方模型凭据。

## 0. 不可违反的边界

1. **不得**把 API Key、访问令牌、Cookie、代理认证、账户标识或完整 `~/.codex/config.toml` 写进仓库、README、日志、Issue、截图或聊天输出。
2. **不得**自动修改用户的第三方模型配置。它属于 `~/.codex/config.toml`、受管配置或用户指定的网关；修改前必须取得用户明确授权。
3. **不得**承诺“额度为零仍能让 Codex 发送消息”。本工具只读取并显示额度，帮助用户在低额度前手动切换到其他已配置模型。
4. **不得**开放 TCP/WebSocket 监听端口；应用只允许通过标准输入输出启动本机 `codex app-server --stdio`。
5. **不得**把 `account/rateLimitResetCredit/consume`、`turn/interrupt` 或任何配置写入接口加入应用。当前版本只允许调用 `account/rateLimits/read`。

## 1. 输入与前置检查

需要的环境：macOS 14+、已安装并登录 Codex、可运行 Swift 6、以及此仓库工作副本。

执行只读检查：

```zsh
swift --version
codex login status
cd <repo-root>
find . -maxdepth 3 -type f -not -path './.build/*' | sort
```

若 `codex login status` 失败：停止安装，要求用户自行登录。大模型不得要求、接收或代填密码、验证码、访问令牌。

## 2. 发布前隐私检查

在任何 `git add`、GitHub 推送或打包动作前，执行只显示文件名的扫描：

```zsh
rg -l -i --glob '!/.build/**' --glob '!*.app/**' \
  '(api[_-]?key|access[_-]?token|refresh[_-]?token|secret|password|bearer[[:space:]]+[A-Za-z0-9._-]{8,}|sk-[A-Za-z0-9_-]{8,})' .
```

- 无输出：继续。
- 有输出：只检查它是否为字段名或安全说明；若可能包含真实值，立即停止，绝不在输出中回显该值，要求用户移除或轮换凭据。
- `.build/`、`.env`、私钥、日志和本机应用包不得提交。

## 3. 构建与单元测试

```zsh
cd <repo-root>
swift test
./scripts/build-app.sh
```

通过条件：测试全部通过，且生成 `.build/release-app/Codex 额度精灵岛.app`。失败时检查 Swift 版本、Codex 可执行文件位置和编译错误；不得以硬编码路径、凭据或关闭安全检查的方式修复。

## 4. 试运行与行为验证

```zsh
open ".build/release-app/Codex 额度精灵岛.app"
```

核验：顶部中央出现深色胶囊；显示“5小时”和“1周”的**剩余**百分比；无法获取额度时不能将旧数据伪装为新数据；由用户决定是否允许 macOS 通知；应用不读取对话文本、不修改 Codex 配置、不终止对话。

真实额度高于 10% 时，不得为了触发通知而消耗额度或调用额度重置。低额度逻辑通过单元测试验证，真实通知由后续自然发生时端到端验证。

## 5. 配置额度刷新频率

默认刷新间隔为 **60 秒**。配置键为 macOS 用户默认值 `com.wyn.codex-quota-island.refreshIntervalSeconds`，有效范围是 **10–3600 秒**；缺失时使用 60，低于 10 自动按 10，高于 3600 自动按 3600。

只有用户明确要求更快提醒，且机器性能足够时，才将其设为 10 秒：

```zsh
defaults write com.wyn.codex-quota-island refreshIntervalSeconds -int 10
```

设置后需重启本工具或其 LaunchAgent 才会生效：

```zsh
launchctl kickstart -k "gui/$(id -u)/com.wyn.codex-quota-island"
```

恢复默认值：

```zsh
defaults delete com.wyn.codex-quota-island refreshIntervalSeconds
launchctl kickstart -k "gui/$(id -u)/com.wyn.codex-quota-island"
```

不要把刷新间隔设为小于 10 秒，也不要把配置写入仓库。较短间隔会提高提醒及时性，但每次查询都会短暂启动 App Server，带来更多短时资源峰值。本机实测一次查询约 2 秒，所以 10 秒间隔理论上会有约 20% 的时间在运行查询进程；先按第 7 节测量实际资源，再决定是否保留该设置。

## 6. 安装为登录启动项

仅在用户明确要求常驻运行且试运行成功后执行：

```zsh
ditto ".build/release-app/Codex 额度精灵岛.app" "/Applications/Codex 额度精灵岛.app"
cp scripts/com.wyn.codex-quota-island.plist "$HOME/Library/LaunchAgents/"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.wyn.codex-quota-island.plist"
launchctl print "gui/$(id -u)/com.wyn.codex-quota-island"
```

成功条件：启动项已加载，且应用进程运行。正常状态下，`codex app-server --stdio` 只在每次查询期间短暂出现，随后退出。

## 7. 资源验收

```zsh
APP_PID=$(pgrep -f '/CodexQuotaIsland.app/Contents/MacOS/CodexQuotaIsland' | head -1)
ps -o pid=,rss=,%cpu=,etime=,command= -p "$APP_PID"
vmmap -summary "$APP_PID" | rg 'Physical footprint'
```

基准：常驻物理内存约 20 MB，空闲 CPU 接近 0%。默认每 60 秒查询一次；若用户设为 10 秒，应额外确认短时 CPU 峰值不会影响其工作。每次查询可能短暂拉起 App Server，约两秒后退出。若出现持续高 CPU、重复崩溃或常驻 App Server，停止发布并定位原因。

## 8. 第三方模型协作方式

本项目不配置模型。若用户已在 Codex 或其他客户端中配置第三方模型：

1. 网关地址与凭据只能保存在用户级配置或提供方安全存储中。
2. 任一额度窗口剩余量 `≤10%` 时，由用户手动切换到目标模型。
3. 使用提供方官方文档验证目标模型是否兼容当前 Codex；不得凭猜测写模型名称、API 路径或鉴权字段。
4. 若需改动 `~/.codex/config.toml`，先向用户展示字段名、目的和回滚方式，等待明确授权。

## 9. 卸载与回滚

仅在用户明确要求时执行：

```zsh
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.wyn.codex-quota-island.plist"
rm "$HOME/Library/LaunchAgents/com.wyn.codex-quota-island.plist"
rm -rf "/Applications/Codex 额度精灵岛.app"
```

回滚只影响本工具，不影响 Codex、ChatGPT 登录、外部模型配置或聊天历史。
