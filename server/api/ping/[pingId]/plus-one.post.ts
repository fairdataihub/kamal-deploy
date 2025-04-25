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

  const updatedPing = await prisma.ping.update({
    where: {
      id: pingId,
    },
    data: {
      plusOneCount: {
        increment: 1,
      },
    },
  });

  return {
    plusOneCount: updatedPing.plusOneCount ?? 0,
  };
});
