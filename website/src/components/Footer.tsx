import Link from "next/link";

export default function Footer() {
  return (
    <footer className="w-full bg-[#1C1917] text-white pt-24 pb-12 px-6 mt-auto">
      <div className="max-w-[1400px] mx-auto">
        <div className="grid grid-cols-2 md:grid-cols-4 gap-8 mb-24">
          
          {/* Footer Column 1 */}
          <div className="flex flex-col gap-4">
            <span className="text-[13px] font-semibold text-white mb-2">Resources</span>
            <Link href="/setup" className="text-[13px] text-[#A8A29E] hover:text-white">Setup</Link>
            <Link href="/faq" className="text-[13px] text-[#A8A29E] hover:text-white">FAQ</Link>
            <Link href="https://github.com/jerryjin/cauchy" className="text-[13px] text-[#A8A29E] hover:text-white">GitHub</Link>
          </div>

          {/* Footer Column 2 */}
          <div className="flex flex-col gap-4">
            <span className="text-[13px] font-semibold text-white mb-2">Legal</span>
            <Link href="/legal/privacy" className="text-[13px] text-[#A8A29E] hover:text-white">Privacy Policy</Link>
            <Link href="/legal/terms" className="text-[13px] text-[#A8A29E] hover:text-white">Terms of Use</Link>
          </div>

        </div>
        
        <div className="pt-8 border-t border-[#44403C] flex flex-col md:flex-row justify-between items-center gap-4">
          <div className="flex items-center gap-6 text-[12px] text-[#A8A29E]">
            <Link href="/legal/terms" className="hover:text-white">Terms of Use</Link>
            <Link href="/legal/privacy" className="hover:text-white">Privacy Policy</Link>
          </div>
          <div className="text-[12px] text-[#A8A29E]">
            Cauchy Open Source
          </div>
        </div>
      </div>
    </footer>
  );
}
