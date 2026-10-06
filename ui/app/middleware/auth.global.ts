// Every page except sign-in and the component sheet needs a signed-in person.
export default defineNuxtRouteMiddleware(async (to) => {
  if (to.path === '/login' || to.path === '/_design') return
  const { load } = useSession()
  const user = await load()
  if (!user) return navigateTo('/login')
})
