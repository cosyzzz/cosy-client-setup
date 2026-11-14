# Cosy Classroom System — Universal Client Setup (`cosy-client-setup`)

Bộ cài đặt công khai chính thức (tương thích mọi môi trường, **luôn bắt buộc kiểm tra & cài đặt phiên bản Client mới nhất** kèm xác thực toàn vẹn SHA-256).

---

## 1. Cài đặt nhanh trên Windows (Windows 7 / 8 / 10 / 11 / Server 2012–2025, x64 & ARM64)

### Cách A — PowerShell (khuyên dùng, chạy được cả khi `ExecutionPolicy Restricted`)
```powershell
irm https://raw.githubusercontent.com/cosyzzz/cosy-client-setup/main/win.ps1 | iex
```

### Cách B — PowerShell với tùy chọn nâng cao (Server riêng / Ticket / Chạy ngầm Session-0)
```powershell
# Chạy ngầm Session-0 SYSTEM (phòng máy / triển khai hàng loạt)
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/cosyzzz/cosy-client-setup/main/win.ps1))) -Bg

# Chỉ định Server URL tùy chỉnh hoặc ép cài lại bản mới nhất
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/cosyzzz/cosy-client-setup/main/win.ps1))) -ServerUrl "https://sykids.dpdns.org" -Force

# Kiểm tra tải + SHA-256 + --selftest mà KHÔNG cài lên máy (Dry / Verify)
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/cosyzzz/cosy-client-setup/main/win.ps1))) -VerifyOnly
```

### Cách C — Command Prompt (`cmd.exe`) / Máy không mở PowerShell / Win7 cũ
```cmd
curl.exe -fsSL https://raw.githubusercontent.com/cosyzzz/cosy-client-setup/main/win.cmd -o "%TEMP%\cosy-win.cmd" && "%TEMP%\cosy-win.cmd"
```
*(Nếu máy không có `curl.exe`, tải trực tiếp [`install.bat`](https://raw.githubusercontent.com/cosyzzz/cosy-client-setup/main/install.bat) hoặc [`CPInstall.exe`](https://github.com/cosyzzz/cosy-client-setup/releases/latest/download/CPInstall.exe) và nhấp đúp để chạy — tự fallback qua PowerShell / WebClient / BITS / certutil.)*

---

## 2. Cài đặt nhanh trên Linux (Ubuntu, Debian, Xubuntu, Fedora, RHEL, Arch, openSUSE, Alpine)

Hỗ trợ tự nhận diện `apt`, `dnf`, `yum`, `pacman`, `zypper`, `apk`, kiến trúc `amd64`/`arm64`, init system (`systemd`, `OpenRC`, hoặc container/WSL), và fallback `curl` -> `wget` -> `python3`:

```bash
curl -fsSL https://raw.githubusercontent.com/cosyzzz/cosy-client-setup/main/linux.sh | sudo bash
```

Hoặc truyền tham số tùy chỉnh:
```bash
curl -fsSL https://raw.githubusercontent.com/cosyzzz/cosy-client-setup/main/linux.sh -o /tmp/cosy-linux.sh
sudo bash /tmp/cosy-linux.sh --server https://sykids.dpdns.org --force
```

---

## 3. Cơ chế "Bắt buộc Client Mới Nhất" & Tương thích mọi môi trường

1. **So sánh phiên bản đa nguồn (`GitHub Release latest` vs `Live Server /update?client&check=1`)**:
   - Bộ cài luôn đối chiếu `version.json` mới nhất trên repo với server đang trỏ tới, **tự động chọn phiên bản cao hơn** (nếu server đang giữ bản cũ hơn hoặc đang offline/bị chặn, bộ cài tự fallback sang bản mới nhất từ GitHub Releases).
2. **Ép nâng cấp an toàn**:
   - Nếu máy đã cài phiên bản cũ hơn, bộ cài tự động dừng/nâng cấp sạch lên bản mới nhất và xác minh dịch vụ (`cpsv` / `cpwg` / `cp-ag` trên Windows; `cpsv.service` / `cpwg.service` trên Linux) chạy ổn định.
3. **Xác thực toàn vẹn SHA-256**:
   - Mọi gói nhị phân & source tarball đều được kiểm tra khớp `SHA-256` trong `version.json` / `SHA256SUMS.txt` trước khi thực thi.
4. **Hồ sơ nhị phân phát hành (`Releases`)**:
   - `CPInstall.exe` / `SySoftwareSetup.exe`: Bộ cài đặt Windows GUI/Headless tích hợp `cp-st.exe`, `cp-ag.exe`, `cp-wd.exe`.
   - `CPUninstall.exe`: Bộ gỡ cài đặt chuẩn có xác thực Recovery Key / mã gỡ từ Dashboard.
   - `Client-Linux-src.tar.gz`: Mã nguồn chuẩn mới nhất để tự biên dịch tối ưu trên mọi distro Linux.
   - `SHA256SUMS.txt` & `version.json`: Bảng băm và metadata phiên bản mới nhất.
