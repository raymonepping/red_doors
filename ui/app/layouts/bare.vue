<template>
  <main id="main-content" class="rd-bare">
    <slot />
  </main>
</template>

<style scoped>
.rd-bare { min-height: 100vh; padding: 32px clamp(16px, 4vw, 48px) 48px; }
</style>
