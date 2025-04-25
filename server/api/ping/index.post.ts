import { z } from "zod";
import { nanoid } from "nanoid";

const pingSchema = z.object({
  username: z.string(),
  location: z.string(),
});

export default defineEventHandler(async (event) => {
  const body = await readValidatedBody(event, (b) => pingSchema.safeParse(b));

  if (!body.success) {
    throw createError({
      status: 400,
      message: "Missing required fields",
    });
  }

  const { username, location } = body.data;

  const ping = await prisma.ping.create({
    data: {
      id: nanoid(),
      username,
      location,
    },
  });

  return ping;
});
