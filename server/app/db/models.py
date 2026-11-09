from __future__ import annotations

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.dialects.sqlite import JSON as SQLITE_JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.types import JSON, Uuid

from app.db.base import Base


class User(Base):
    __tablename__ = "users"
    __table_args__ = (UniqueConstraint("apple_sub"), UniqueConstraint("dev_handle"))

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    apple_sub: Mapped[str | None] = mapped_column(String(255), nullable=True)
    dev_handle: Mapped[str | None] = mapped_column(String(255), nullable=True)
    display_name: Mapped[str] = mapped_column(String(80))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class ArenaRow(Base):
    __tablename__ = "arenas"

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    owner_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("users.id"))
    name: Mapped[str] = mapped_column(String(80))
    data: Mapped[dict] = mapped_column(JSON().with_variant(SQLITE_JSON, "sqlite"))
    version: Mapped[int] = mapped_column(Integer, default=1)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class GameRow(Base):
    __tablename__ = "games"

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    join_code: Mapped[str] = mapped_column(String(6), index=True)
    host_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("users.id"))
    status: Mapped[str] = mapped_column(String(32), default="lobby")
    arena_snapshot: Mapped[dict] = mapped_column(JSON().with_variant(SQLITE_JSON, "sqlite"))
    preset_snapshot: Mapped[dict] = mapped_column(JSON().with_variant(SQLITE_JSON, "sqlite"))
    seed: Mapped[int] = mapped_column(Integer)
    result: Mapped[dict | None] = mapped_column(
        JSON().with_variant(SQLITE_JSON, "sqlite"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    players: Mapped[list[GamePlayerRow]] = relationship(back_populates="game")


class GamePlayerRow(Base):
    __tablename__ = "game_players"
    __table_args__ = (UniqueConstraint("game_id", "user_id"),)

    game_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("games.id"), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("users.id"), primary_key=True)
    role: Mapped[str] = mapped_column(String(16), default="unassigned")
    status: Mapped[str] = mapped_column(String(16), default="active")
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    game: Mapped[GameRow] = relationship(back_populates="players")


class GameEventRow(Base):
    __tablename__ = "game_events"

    game_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("games.id"), primary_key=True)
    seq: Mapped[int] = mapped_column(Integer, primary_key=True)
    type: Mapped[str] = mapped_column(String(64))
    payload: Mapped[dict] = mapped_column(JSON().with_variant(SQLITE_JSON, "sqlite"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    # Precise location never persisted in MVP. TODO: Phase 2 AES-GCM trails.


class AuditLog(Base):
    __tablename__ = "audit_log"

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    actor_id: Mapped[UUID | None] = mapped_column(Uuid, nullable=True)
    action: Mapped[str] = mapped_column(String(64))
    detail: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
