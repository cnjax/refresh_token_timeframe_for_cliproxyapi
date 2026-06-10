# 触发令牌管理 (Trigger Token Management)

此目录包含用于通过在所有活跃凭据上触发 `/v1/chat/completions` 请求来轮换和刷新身份验证令牌的脚本。

## 脚本

### `refresh_via_v1.sh` (Shell 版本)

此脚本自动执行验证和刷新验证文件的过程。

### `refresh_via_v1.py` (Python 版本)

相同逻辑的 Python 实现，提供更好的错误处理和跨平台兼容性。

## 工作原理

1. 从代理获取所有当前活跃的验证文件。
2. 暂时禁用它们。
3. 逐个遍历，启用它，向 `/v1/chat/completions` 发送 "ping" 请求，然后再次禁用它。
4. 在完成或中断时恢复所有文件的原始活跃状态。

#### 配置

脚本使用具有默认值的环境变量：

- `MANAGEMENT_KEY`: 管理 API 的密钥 (默认值: `TEST_MANAGEMENT_KEY`)。
- `API_KEY`: 代理的有效 API 密钥 (默认值: `sk-TEST_API_KEY`)。
- `BASE_URL`: CLI Proxy API 的基础 URL (默认值: `http://127.0.0.1:8317`)。

#### 使用方法

**Shell:**
```bash
chmod +x refresh_via_v1.sh
./refresh_via_v1.sh
```

**Python:**
```bash
python3 refresh_via_v1.py
```

覆盖配置：
```bash
MANAGEMENT_KEY="your-secret" BASE_URL="https://proxy.example.com" ./refresh_via_v1.sh
```

## 定时任务 (Crontab)

要自动运行刷新（例如，每天早上 7:00 和中午 12:00），请将以下内容添加到您的 crontab (`crontab -e`)：

```cron
0 7,12 * * * /bin/bash /path/to/CLIProxyAPI/triggertoken/refresh_via_v1.sh >> /path/to/CLIProxyAPI/triggertoken/refresh.log 2>&1
```

## 要求

- `curl`
- `jq` (用于 Shell 版本)
- `python3` 和 `requests` 库 (用于 Python 版本)
