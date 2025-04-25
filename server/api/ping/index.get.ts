// Returns a list of published datasets
export default defineEventHandler(async (_event) => {
  const pings = await prisma.ping.findMany({ orderBy: { createdAt: "desc" } });

  return pings ?? [];
});
