export default defineEventHandler(async (event) => {
  const { pingId } = event.context.params as { pingId: string };

  const ping = await prisma.ping.findUnique({
    where: {
      id: pingId,
    },
  });

  if (!ping) {
    throw createError({
      status: 404,
      message: "Ping not found",
    });
  }

  await prisma.ping.delete({
    where: {
      id: pingId,
    },
  });

  return {
    id: pingId,
  };
});
