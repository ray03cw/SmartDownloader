#!/bin/bash

# --- 💖 実行場所を自動で特定する従順なロジック 💖 ---
WORKDIR="$(cd "$(dirname "$0")" && pwd)"
COOKIE_FILE="${WORKDIR}/cookies.txt"
cd "${WORKDIR}"

while true; do
    clear
    echo "============================================"
    echo "     yt-dlp Smart Downloader (Linux Edition)"
    echo "============================================"

    # yt-dlp が存在するかチェック (システムパス or カレントディレクトリ)
    YTDLP_BIN=""
    if [ -f "${WORKDIR}/yt-dlp" ]; then
        YTDLP_BIN="${WORKDIR}/yt-dlp"
    elif command -v yt-dlp >/dev/null 2>&1; then
        YTDLP_BIN="yt-dlp"
    else
        echo "[!] ERROR: yt-dlp が見つかりませんわッ！"
        echo "場所: ${WORKDIR}"
        read -p "Press Enter to exit..."
        exit 1
    fi

    # アプデチェック
    "${YTDLP_BIN}" -U > /dev/null 2>&1
    echo "[1/3] Update: Checked."

    if [ -f "${COOKIE_FILE}" ]; then echo "[2/3] Cookies: Found."; else echo "[2/3] Cookies: [!] NOT FOUND."; fi
    if command -v ffmpeg >/dev/null 2>&1 || [ -f "${WORKDIR}/ffmpeg" ]; then echo "[3/3] FFmpeg: Found."; else echo "[3/3] FFmpeg: [!] NOT FOUND."; fi
    echo ""

    # --- URL_INPUT ---
    while true; do
        echo "[9: Stop Script (Exit)]"
        read -p "Enter YouTube URL (Leave blank for Clipboard): " RAW_URL

        if [ "${RAW_URL}" = "9" ]; then
            echo "Stopping..."
            exit 0
        fi

        if [ -z "${RAW_URL}" ]; then
            if command -v xclip >/dev/null 2>&1; then
                URL="$(xclip -selection clipboard -o 2>/dev/null)"
            elif command -v xsel >/dev/null 2>&1; then
                URL="$(xsel -b -o 2>/dev/null)"
            fi
        else
            URL="${RAW_URL}"
        fi

        # リスト無視（URLのクリーンアップ：&のカット）
        URL="${URL%%&*}"

        if [ -z "${URL}" ]; then
            echo "[!] URLが空か、クリップボードから取得できませんでした。"
            continue
        fi

        echo "[Analyzing Video Formats...]"

        COOKIE_ARG=""
        if [ -f "${COOKIE_FILE}" ]; then
            COOKIE_ARG="--cookies ${COOKIE_FILE}"
        fi

        JSON_META=$("${YTDLP_BIN}" ${COOKIE_ARG} --no-check-certificate --dump-json "${URL}" 2>/dev/null)

        if [ -z "${JSON_META}" ]; then
            echo "[!] 解析に失敗しましたわ。パスやURLを確認してくださいッ！"
            continue
        fi

        TITLE=$(echo "${JSON_META}" | jq -r '.title // empty')
        MAX_H=$(echo "${JSON_META}" | jq -r '[.formats[] | select(.vcodec != "none" and .height != null) | .height] | max // empty')
        
        HAS_AV1=$(echo "${JSON_META}" | jq -r 'if ([.formats[] | select(.vcodec != "none") | .vcodec | contains("av01")] | any) then 1 else 0 end')
        HAS_AVC=$(echo "${JSON_META}" | jq -r 'if ([.formats[] | select(.vcodec != "none") | .vcodec | contains("avc1")] | any) then 1 else 0 end')

        if [ -z "${TITLE}" ]; then
            echo "[!] タイトル取得失敗。"
            continue
        fi

        echo ""
        echo "--------------------------------------------"
        echo " TARGET: ${TITLE}"
        echo "--------------------------------------------"

        read -p "1: Yes / 0: Back / 9: Exit: " CONF_V
        if [ "${CONF_V}" = "9" ]; then exit 0; fi
        if [ "${CONF_V}" = "0" ]; then continue; fi
        if [ "${CONF_V}" = "1" ]; then break; fi
    done

    # --- PATH_MENU ---
    echo ""
    echo "[Select Destination Path]"
    echo "1: Current Folder (${WORKDIR})"
    echo "2: ~/ダウンロード (Linux Default)"
    echo "3: ~/Downloads"
    echo "4: Custom Input"
    echo "0: Back"
    read -p "Select: " PC

    case "${PC}" in
        0) continue ;;
        1) DP="${WORKDIR}" ;;
        2) DP="${HOME}/ダウンロード" ;;
        3) DP="${HOME}/Downloads" ;;
        4) read -p "Enter Full Path: " DP ;;
        *) DP="${WORKDIR}" ;;
    esac

    if [ -z "${DP}" ]; then DP="${WORKDIR}"; fi
    mkdir -p "${DP}" 2>/dev/null
    DEST_PATH="${DP}"

    # --- MODE_MENU ---
    echo ""
    echo "[Select Mode]"
    echo "1: Video (MP4)"
    echo "2: Audio (M4A/MP3)"
    echo "0: Back"
    read -p "Select: " MODE

    if [ "${MODE}" = "0" ]; then continue; fi

    OPTS="--no-playlist --paths ${DEST_PATH} --no-check-certificate --embed-thumbnail --add-metadata"
    if [ -f "${COOKIE_FILE}" ]; then
        OPTS="${OPTS} --cookies ${COOKIE_FILE}"
    fi

    if [ "${MODE}" = "2" ]; then
        # --- DL_AUDIO_SELECT ---
        echo ""
        echo "[Select Audio Format] 1: M4A / 2: MP3 (320k) / 0: Back"
        read -p "Select: " AMC
        if [ "${AMC}" = "0" ]; then continue; fi

        if [ "${AMC}" = "1" ]; then
            "${YTDLP_BIN}" ${OPTS} -f "ba[ext=m4a]/ba" -o "%(title)s.%(ext)s" "${URL}"
        elif [ "${AMC}" = "2" ]; then
            "${YTDLP_BIN}" ${OPTS} -f "ba" --extract-audio --audio-format mp3 --audio-quality 0 -o "%(title)s.%(ext)s" "${URL}"
        fi
    else
        # --- RES_MENU (細かい解像度選択) ---
        echo ""
        echo "[Resolution Selection] Max: ${MAX_H}p"
        
        # 最大画質に応じて動的に選択肢を表示
        if [ "${MAX_H}" -ge 2160 ] 2>/dev/null; then echo "1: 2160p (4K)"; fi
        if [ "${MAX_H}" -ge 1440 ] 2>/dev/null; then echo "2: 1440p (2K)"; fi
        if [ "${MAX_H}" -ge 1080 ] 2>/dev/null; then echo "3: 1080p (FHD)"; fi
        if [ "${MAX_H}" -ge 720 ]  2>/dev/null; then echo "4: 720p (HD)"; fi
        if [ "${MAX_H}" -ge 480 ]  2>/dev/null; then echo "5: 480p (SD)"; fi
        if [ "${MAX_H}" -ge 360 ]  2>/dev/null; then echo "6: 360p"; fi
        echo "7: Best / Auto (${MAX_H}p)"
        echo "0: Back"
        read -p "Select: " RC

        case "${RC}" in
            0) continue ;;
            1) L="2160" ;;
            2) L="1440" ;;
            3) L="1080" ;;
            4) L="720" ;;
            5) L="480" ;;
            6) L="360" ;;
            7) L="${MAX_H}" ;;
            *) L="${MAX_H}" ;;
        esac

        # --- FORMAT_MENU ---
        VT=""
        if [ "${HAS_AV1}" = "1" ] && [ "${HAS_AVC}" = "1" ]; then
            echo ""
            echo "[Both Formats Found] 1: AV1 / 2: AVC / 3: Both / 0: Back"
            read -p "Select: " VT
            if [ "${VT}" = "0" ]; then continue; fi
        else
            if [ "${HAS_AV1}" = "1" ]; then
                echo "[AV1 found. Proceeding...]"
                VT="1"
            elif [ "${HAS_AVC}" = "1" ]; then
                echo "[AV1 not found. Proceeding with AVC...]"
                VT="2"
            else
                echo "[Preferred codecs not found. Downloading best available...]"
                VT="99"
            fi
        fi

        case "${VT}" in
            1)
                "${YTDLP_BIN}" ${OPTS} --merge-output-format mp4 -f "bestvideo[height<=${L}][vcodec*=av01]+bestaudio/best[vcodec*=av01][height<=${L}]/best[height<=${L}]" -o "%(title)s [AV1].%(ext)s" "${URL}"
                ;;
            2)
                "${YTDLP_BIN}" ${OPTS} --merge-output-format mp4 -f "bestvideo[height<=${L}][vcodec*=avc1]+bestaudio/best[vcodec*=avc1][height<=${L}]/best[height<=${L}]" -o "%(title)s [AVC].%(ext)s" "${URL}"
                ;;
            3)
                "${YTDLP_BIN}" ${OPTS} --merge-output-format mp4 -f "bestvideo[height<=${L}][vcodec*=av01]+bestaudio/best[vcodec*=av01][height<=${L}]/best[height<=${L}]" -o "%(title)s [AV1].%(ext)s" "${URL}"
                "${YTDLP_BIN}" ${OPTS} --merge-output-format mp4 -f "bestvideo[height<=${L}][vcodec*=avc1]+bestaudio/best[vcodec*=avc1][height<=${L}]/best[height<=${L}]" -o "%(title)s [AVC].%(ext)s" "${URL}"
                ;;
            *)
                "${YTDLP_BIN}" ${OPTS} --merge-output-format mp4 -f "bestvideo[height<=${L}]+bestaudio/best[height<=${L}]" -o "%(title)s.%(ext)s" "${URL}"
                ;;
        esac
    fi

    echo ""
    echo "Process finished."
    read -p "Press Enter to return to main menu..."
done
