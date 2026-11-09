from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.config import Settings
from app.db.base import Base


def make_engine(url: str):
    connect_args = {}
    if url.startswith("sqlite"):
        connect_args["check_same_thread"] = False
    return create_async_engine(url, connect_args=connect_args)


def make_session_factory(engine) -> async_sessionmaker[AsyncSession]:
    return async_sessionmaker(engine, expire_on_commit=False)


async def create_schema(engine) -> None:
    """Create tables for an empty local database.

    Versioned deploys use ``alembic upgrade head``. ``create_all`` stays so
    tests and a first-boot SQLite file match the models, including the partial
    unique index on live join codes.
    """
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


def lifespan_resources(settings: Settings):
    engine = make_engine(settings.manhunt_database_url)
    factory = make_session_factory(engine)
    return engine, factory


async def session_dep(factory: async_sessionmaker[AsyncSession]) -> AsyncIterator[AsyncSession]:
    async with factory() as session:
        yield session
