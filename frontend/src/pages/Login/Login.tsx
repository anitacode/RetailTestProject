import LoginIntro from "@/pages/Login/components/LoginIntro";
import LoginForm from "@/pages/Login/components/LoginForm";

export default function Login() {
  return (
    <main className="grid min-h-screen grid-cols-[1fr_1fr] max-md:grid-cols-[1fr]">
      <section className="relative flex min-h-screen flex-col justify-between overflow-hidden bg-slate-900 px-15 py-12 text-slate-50 after:pointer-events-none after:absolute after:right-[-130px] after:bottom-[-160px] after:h-85 after:w-85 after:rounded-full after:border after:border-solid after:border-[#ffffff09] after:shadow-[0_0_0_50px_#ffffff03,_0_0_0_100px_#ffffff03] after:content-[''] max-lg:p-[35px] max-md:min-h-auto max-md:p-[27px] 2xl:px-22.5 2xl:py-15">
        <LoginIntro />
      </section>
      <section className="relative flex items-center justify-center bg-slate-50 px-7.5 pt-15 pb-25 max-md:px-[25px] max-md:pt-10 max-md:pb-[85px]">
        <LoginForm />
      </section>
    </main>
  );
}
