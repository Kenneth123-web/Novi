// The documented way to type `env` from `cloudflare:test`: point ProvidedEnv
// at the generated Env rather than re-declaring the bindings by hand.
declare module "cloudflare:test" {
  interface ProvidedEnv extends Env {}
}
