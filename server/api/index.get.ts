// Returns a server active message
export default defineEventHandler(async (_event) => {
  return new Response("Hello from server :)");
});
