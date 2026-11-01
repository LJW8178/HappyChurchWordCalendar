# Synology DSM 배포 (Git clone 방식)

이 절차는 NAS에서 API 서버를 실행하고, Flutter APK는 Windows PC에서 별도로 빌드합니다. DSM에서 Container Manager를 설치하고 `docker` 공유 폴더(Volume 1), `wordcalendar-data` 공유 폴더(Volume 1)를 만드세요. 선택적으로 Hyper Backup용 `wordcalendar-backup` 공유 폴더를 Volume 2에 만듭니다. `wordcalendar-data`의 권한은 관리자에게만 주고 guest 접근은 끕니다. SSH는 DSM 제어판에서 필요한 동안만 켜세요.

DSM SSH에 로그인한 뒤 `git --version`과 `sudo docker compose version`을 확인합니다. Git CLI가 없으면 이 Git clone 절차를 진행할 수 없으므로 DSM에서 제공하는 방법으로 Git CLI를 설치하거나, 저장소 파일을 PC에서 NAS로 복사하는 README의 Windows 배치 파일 절차를 사용하세요. SSH 로그인 계정이 `docker` 공유 폴더에 쓸 수 있어야 합니다.

아래는 저장소의 `v1` 브랜치를 `/volume1/docker/wordcalendar`에 받는 예입니다. 폴더가 이미 있으면 clone하지 말고 먼저 그 저장소 상태를 확인하세요.

```sh
cd /volume1/docker
git clone --branch v1 --single-branch https://github.com/booneel/HappyChurchWordCalendar.git wordcalendar
cd /volume1/docker/wordcalendar
```

저장소를 업데이트할 때는 NAS에서 아래처럼 진행합니다. 로컬에서 수정한 파일이 있으면 먼저 별도로 보관하고 내용을 확인하세요. `.env`와 영구 데이터는 Git으로 관리하지 않습니다.

```sh
cd /volume1/docker/wordcalendar
git status --short
git pull --ff-only origin v1
```

이 프로젝트의 원본은 Git 저장소 `python/` 및 `deploy/synology/` 아래에 있습니다. 첫 실행 스크립트가 거기서 `app/` 빌드 폴더와 루트 `compose.yaml`을 준비합니다. NAS의 `/volume1/wordcalendar-data` 공유 폴더도 먼저 만들어야 합니다.

On a first installation, create the private token file:

```sh
cd /volume1/docker/wordcalendar
sudo sh deploy/synology/generate_tokens.sh
```

The script writes `.env` with separate random user and admin tokens, sets mode `600`, and never prints the token values. It refuses to overwrite an existing `.env`. Leave the two push settings empty unless the FCM relay is configured. Keep the token values in a password manager; never commit or share `.env`.

Deploy or update the API:

```sh
cd /volume1/docker/wordcalendar
sudo sh deploy/synology/deploy_on_synology.sh
```

The deploy script prepares `compose.yaml` and `app/` from tracked repository files, creates `data/` and `backups/` under the shared data folder, checks the token lengths and Compose configuration, restricts `.env` permissions, then rebuilds and starts the container. It prints service status and recent logs if startup fails. It does not overwrite `.env` or the content of the data folders.

Check startup and the two API routes on the NAS:

```sh
cd /volume1/docker/wordcalendar
sudo docker compose ps
sudo docker compose logs --tail=100 wordcalendar-api
```

For token checks without typing secrets into shell history, load the generated values from `.env` into shell variables and run the requests:

```sh
WORDCALENDAR_NAS_TOKEN=$(awk -F= '$1=="WORDCALENDAR_NAS_TOKEN" {print $2}' .env)
WORDCALENDAR_NAS_ADMIN_TOKEN=$(awk -F= '$1=="WORDCALENDAR_NAS_ADMIN_TOKEN" {print $2}' .env)
curl -i -H "Authorization: Bearer $WORDCALENDAR_NAS_TOKEN" http://127.0.0.1:8787/api/settings/pdf
curl -i -H "Authorization: Bearer $WORDCALENDAR_NAS_ADMIN_TOKEN" http://127.0.0.1:8787/api/admin/check
unset WORDCALENDAR_NAS_TOKEN WORDCALENDAR_NAS_ADMIN_TOKEN
```

Both API responses should be HTTP 200. The Compose file binds port 8787 to NAS localhost only. For remote access, connect the NAS and phone to the same Tailscale network, then configure Tailscale Serve to proxy `http://127.0.0.1:8787` and use its HTTPS device address in the app. Do not expose port 8787 directly to the internet.

If migrating existing Firebase content, follow the root README's export and copy steps **before the first server start**, especially for `qna.json` and `stats.json`; the server imports those into SQLite on startup. For a new install, the API can start without imported content, but the calendar PDF view needs an initial `current.pdf` (or upload one through the app's admin function after connecting).

To build the app, run `deploy\synology\build_nas_apk.bat` on a Windows PC with Flutter and Android SDK installed. Enter the Tailscale HTTPS URL and the `.env` user token when prompted. The user token is embedded in the APK; never put the admin token in the build command. Install the resulting `build\app\outputs\flutter-apk\wordcalendar-nas.apk` on the phone and connect Tailscale.

The Windows `deploy_to_nas.bat` remains an alternative for copying files from a Windows PC over SSH/SCP. `build_nas_apk.bat` is also a PC-side task: build the Android APK on a computer with Flutter and the Android SDK, then install it on the phone. DSM is only used to host the API and data.
