"""Сервис сохранения сообщений: текст + скачивание медиа на диск."""

import os
from datetime import datetime, timezone

from aiogram.types import Message

from config import FILES_DIR, MAX_FILE_SIZE, log
from core import bot
from db import db

MEDIA_ATTRS = ("photo", "video", "voice", "audio", "document", "sticker",
               "video_note", "animation")


def default_ext(attr: str, media) -> str:
    """Расширение для медиа без file_name (стикеры, фото, кружки и т.п.)."""
    if attr == "photo":
        return ".jpg"
    if attr == "voice":
        return ".ogg"
    if attr in ("video", "video_note", "animation"):
        return ".mp4"
    if attr == "sticker":
        if getattr(media, "is_video", False):
            return ".webm"
        if getattr(media, "is_animated", False):
            return ".tgs"
        return ".webp"
    return ""


async def save_message(m: Message, conn=None, files_dir: str | None = None) -> int:
    """Сохраняет сообщение в БД, скачивает медиа. Возвращает id записи.
    conn/files_dir — куда писать (по умолчанию основные БД и папка)."""
    conn = conn or db()
    files_dir = files_dir or FILES_DIR
    if m.text:
        msg_type, text = "text", m.text
    elif m.caption:
        msg_type, text = m.content_type, m.caption
    else:
        msg_type, text = m.content_type, None

    # скачиваем медиа сразу — после удаления сообщения файл может стать недоступен
    file_path = None
    for attr in MEDIA_ATTRS:
        media = getattr(m, attr, None)
        if not media:
            continue
        if attr == "photo":
            media = media[-1]  # самое большое превью
        if getattr(media, "file_size", None) and media.file_size > MAX_FILE_SIZE:
            text = (text or "") + " [файл >20МБ, не скачан]"
            break
        try:
            ext = ""
            if getattr(media, "file_name", None):
                ext = os.path.splitext(media.file_name)[1]
            else:
                ext = default_ext(attr, media)
            dest = os.path.join(
                files_dir, f"{m.chat.id}_{m.message_id}_{media.file_unique_id}{ext}"
            )
            await bot.download(media.file_id, destination=dest)
            file_path = dest
        except Exception:
            log.exception("Не удалось скачать медиа %s/%s", m.chat.id, m.message_id)
        break

    conn.execute(
        "INSERT INTO messages (chat_id, message_id, user_id, username, full_name,"
        " msg_type, text, file_path, date) VALUES (?,?,?,?,?,?,?,?,?)",
        (
            m.chat.id,
            m.message_id,
            m.from_user.id if m.from_user else None,
            m.from_user.username if m.from_user else None,
            m.from_user.full_name if m.from_user else None,
            msg_type,
            text,
            file_path,
            (m.date or datetime.now(timezone.utc)).isoformat(),
        ),
    )
    conn.commit()
    return conn.execute("SELECT last_insert_rowid()").fetchone()[0]
