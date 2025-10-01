<script setup lang="ts">
import { faker } from "@faker-js/faker";
import { generateUsername } from "unique-username-generator";
import type { Ping } from "@prisma/client";

const toast = useToast();

const pings = ref<Ping[]>([]);
const pingAddLoading = ref(false);
const pingPlusOneLoading = ref("");

const { data, error } = await useFetch("/api/ping", {});

if (error.value) {
  toast.add({
    title: "There was an error",
    description: error.value.message,
    icon: "material-symbols:error",
  });
}

if (data.value) {
  pings.value = data.value as unknown as Ping[];
}

const addPing = async () => {
  const d = {
    username: generateUsername("-", 5),
    location: `${faker.location.city()}, ${faker.location.country()}`,
  };

  pingAddLoading.value = true;

  await $fetch("/api/ping", {
    method: "POST",
    body: JSON.stringify(d),
  })
    .then((r) => {
      // add the ping to the beginning of the list
      pings.value.unshift(r as unknown as Ping);

      if ("id" in r) {
        toast.add({
          title: "Ping added",
          icon: "basil:add-solid",
          color: "success",
        });
      }
    })
    .catch((e) => {
      toast.add({
        title: "There was an error",
        description: e.message,
        icon: "material-symbols:error",
        color: "error",
      });
    })
    .finally(() => {
      pingAddLoading.value = false;
    });
};

const plusOne = async (pingId: string) => {
  pingPlusOneLoading.value = pingId;

  await $fetch(`/api/ping/${pingId}/plus-one`, {
    method: "POST",
  })
    .then((r) => {
      if ("plusOneCount" in r) {
        const ping = pings.value.find((p) => p.id === pingId);
        if (ping) {
          ping.plusOneCount = r.plusOneCount;
        }
      }
    })
    .catch((e) => {
      toast.add({
        title: "There was an error",
        description: e.message,
        icon: "material-symbols:error",
        color: "error",
      });
    })
    .finally(() => {
      pingPlusOneLoading.value = "";
    });
};

const deletePing = async (pingId: string) => {
  await $fetch(`/api/ping/${pingId}`, {
    method: "DELETE",
  })
    .then((r) => {
      if ("id" in r) {
        toast.add({
          title: "Ping deleted",
          icon: "ic:baseline-delete",
          color: "success",
        });
      }
    })
    .catch((e) => {
      toast.add({
        title: "There was an error",
        description: e.message,
        icon: "material-symbols:error",
        color: "error",
      });
    })
    .finally(() => {
      pings.value = pings.value.filter((p) => p.id !== pingId);
    });
};
</script>

<template>
  <div
    class="mx-auto flex h-screen max-w-6xl flex-col items-center gap-4 px-3 pt-4"
  >
    <div
      class="flex w-full items-center justify-between border-b border-dashed border-slate-300 pb-4"
    >
      <h1 class="text-2xl font-bold text-(--ui-primary)">Ping</h1>

      <UButton :loading="pingAddLoading" @click="addPing"> Add Ping </UButton>
    </div>

    <div v-if="pings.length === 0" class="flex flex-col items-center gap-4">
      <div class="flex flex-col items-center gap-4">
        <div class="flex items-center gap-2">
          <UIcon name="heroicons-outline:user-add" size="2xl" />

          <span class="text-lg text-slate-500">No Pings</span>
        </div>

        <p class="text-lg text-slate-500">Add a ping to get started</p>
      </div>
    </div>

    <div v-else class="w-full">
      <TransitionGroup name="list" tag="div" class="flex w-full flex-col gap-4">
        <div
          v-for="ping in pings"
          :key="ping.id"
          class="flex w-full items-center justify-between gap-2"
        >
          <div class="flex items-center gap-2">
            <UIcon name="lucide:user-circle" size="2xl" />

            <span class="text-lg text-slate-500">{{ ping.username }}</span>

            <span class="text-xs text-slate-500">
              <ClientOnly>
                ({{ $dayjs(ping.createdAt).fromNow() }})
              </ClientOnly>
            </span>
          </div>

          <div class="flex items-center gap-2">
            <p class="text-lg text-slate-500">
              {{ ping.location }}
            </p>

            <UButton
              variant="outline"
              color="neutral"
              icon="icon-park-solid:like"
              size="sm"
              :loading="pingPlusOneLoading === ping.id"
              @click="plusOne(ping.id)"
            >
              <USeparator orientation="vertical" class="h-4 px-1" />

              <span class="text-sm text-slate-500">{{
                ping.plusOneCount
              }}</span>
            </UButton>

            <UButton
              icon="material-symbols:delete"
              size="sm"
              variant="outline"
              color="error"
              @click="deletePing(ping.id)"
            />
          </div>
        </div>
      </TransitionGroup>
    </div>
  </div>
</template>
