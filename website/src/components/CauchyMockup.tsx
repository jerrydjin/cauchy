import {
  FileText,
  Search,
  ChevronLeft,
  ChevronRight,
  Home,
  ZoomIn,
  ZoomOut
} from "lucide-react";

export default function CauchyMockup() {
  return (
    <div className="w-full aspect-[16/10] bg-[#1E1E1E] rounded-xl border border-[#3C3C3C] overflow-hidden shadow-2xl relative flex flex-col font-sans text-white select-none">
      
      {/* Header (Title Bar) */}
      <div className="h-12 w-full border-b border-[#2C2C2C] bg-[#252525] flex items-center justify-between px-4 shrink-0 z-20">
        
        {/* Left: Traffic Lights */}
        <div className="flex items-center gap-2 w-1/3">
          <div className="w-3 h-3 rounded-full bg-[#FF5F56] border border-[#E0443E]"></div>
          <div className="w-3 h-3 rounded-full bg-[#FFBD2E] border border-[#DEA123]"></div>
          <div className="w-3 h-3 rounded-full bg-[#27C93F] border border-[#1AAB29]"></div>
        </div>

        {/* Center: Document Title Tab */}
        <div className="flex-1 flex justify-center">
          <div className="bg-[#1E1E1E] px-4 py-1.5 rounded-md text-[12px] font-medium text-[#D4D4D4] flex items-center gap-2 border border-[#2C2C2C] shadow-sm">
            <FileText className="w-3.5 h-3.5 text-[#9CDCFE]" />
            part_a_a2_metricspaces_notes
          </div>
        </div>

        {/* Right: Toolbar Controls */}
        <div className="flex items-center justify-end gap-3 w-1/3 text-[#A0A0A0]">
          <div className="hover:text-white hover:bg-[#3C3C3C] p-1.5 rounded transition-colors cursor-pointer">
            <Home className="w-4 h-4" />
          </div>
          <div className="hover:text-white hover:bg-[#3C3C3C] p-1.5 rounded transition-colors cursor-pointer">
            <FileText className="w-4 h-4" />
          </div>
          <div className="hover:text-white hover:bg-[#3C3C3C] p-1.5 rounded transition-colors cursor-pointer">
            <Search className="w-4 h-4" />
          </div>
          <div className="h-4 w-px bg-[#444] mx-1"></div>
          <div className="hover:text-white hover:bg-[#3C3C3C] p-1.5 rounded transition-colors cursor-pointer">
            <ZoomOut className="w-4 h-4" />
          </div>
          <div className="hover:text-white hover:bg-[#3C3C3C] p-1.5 rounded transition-colors cursor-pointer">
            <ZoomIn className="w-4 h-4" />
          </div>
          <div className="h-4 w-px bg-[#444] mx-1"></div>
          <div className="hover:text-white hover:bg-[#3C3C3C] p-1.5 rounded transition-colors cursor-pointer">
            <ChevronLeft className="w-4 h-4" />
          </div>
          <div className="text-[12px] font-medium text-[#D4D4D4] w-4 text-center">
            7
          </div>
          <div className="hover:text-white hover:bg-[#3C3C3C] p-1.5 rounded transition-colors cursor-pointer">
            <ChevronRight className="w-4 h-4" />
          </div>
        </div>
      </div>

      {/* Main Content Area (3 Columns) */}
      <div className="flex-1 flex overflow-hidden bg-[#1E1E1E]">
        
        {/* Left Column (Thumbnails) */}
        <div className="w-40 border-r border-[#2C2C2C] bg-[#252525] flex flex-col items-center py-4 gap-6 overflow-y-auto shrink-0 hidden md:flex">
          
          {/* Thumbnail 5 */}
          <div className="flex flex-col items-center gap-2 w-full">
            <div className="w-[85%] aspect-[1/1.4] bg-white rounded-sm shadow-sm opacity-90 p-2 flex flex-col gap-1.5 border border-[#333]">
              <div className="w-1/2 h-1 bg-[#D0D0D0] mx-auto mb-2"></div>
              <div className="w-full h-1 bg-[#E0E0E0]"></div>
              <div className="w-full h-1 bg-[#E0E0E0]"></div>
              <div className="w-3/4 h-1 bg-[#E0E0E0]"></div>
              <div className="w-full h-1 bg-[#E0E0E0] mt-1"></div>
              <div className="w-5/6 h-1 bg-[#E0E0E0]"></div>
            </div>
            <span className="text-[10px] text-[#888]">5</span>
          </div>

          {/* Thumbnail 6 */}
          <div className="flex flex-col items-center gap-2 w-full">
            <div className="w-[85%] aspect-[1/1.4] bg-white rounded-sm shadow-sm opacity-90 p-2 flex flex-col gap-1.5 border border-[#333]">
              <div className="w-full h-1 bg-[#E0E0E0]"></div>
              <div className="w-full h-1 bg-[#E0E0E0]"></div>
              <div className="w-[40%] h-1 bg-[#E0E0E0]"></div>
              
              <div className="w-3/4 h-2 bg-[#F0F0F0] mx-auto my-1 rounded-sm"></div>

              <div className="w-full h-1 bg-[#E0E0E0]"></div>
              <div className="w-[90%] h-1 bg-[#E0E0E0]"></div>
            </div>
            <span className="text-[10px] text-[#888]">6</span>
          </div>

          {/* Thumbnail 7 (Active) */}
          <div className="flex flex-col items-center gap-2 w-full">
            <div className="w-[85%] aspect-[1/1.4] bg-white rounded-sm shadow-md opacity-100 p-2 flex flex-col gap-1.5 border-2 border-[#007AFF] ring-2 ring-[#007AFF]/20">
              <div className="w-full h-1 bg-[#E0E0E0]"></div>
              <div className="w-[80%] h-1 bg-[#E0E0E0]"></div>
              <div className="w-[90%] h-1 bg-[#E0E0E0]"></div>
              
              <div className="w-full h-1.5 bg-[#FFF5B1] my-1 rounded-sm"></div>
              
              <div className="w-1/3 h-1.5 bg-[#D0D0D0] mt-1"></div>
              <div className="w-full h-1 bg-[#E0E0E0]"></div>
              <div className="w-full h-1 bg-[#E0E0E0]"></div>
              <div className="w-[85%] h-1 bg-[#E0E0E0]"></div>
            </div>
            <span className="text-[10px] text-[#E0E0E0] font-medium">7</span>
          </div>

          {/* Thumbnail 8 */}
          <div className="flex flex-col items-center gap-2 w-full">
            <div className="w-[85%] aspect-[1/1.4] bg-white rounded-sm shadow-sm opacity-90 p-2 flex flex-col gap-1.5 border border-[#333]">
              <div className="w-full h-1 bg-[#E0E0E0]"></div>
              <div className="w-[70%] h-1 bg-[#E0E0E0]"></div>
              
              <div className="w-2/3 h-2 bg-[#F0F0F0] mx-auto my-1 rounded-sm"></div>
              
              <div className="w-full h-1 bg-[#E0E0E0]"></div>
              <div className="w-[95%] h-1 bg-[#E0E0E0]"></div>
            </div>
            <span className="text-[10px] text-[#888]">8</span>
          </div>
        </div>

        {/* Center Column (PDF Reader) */}
        <div className="flex-1 flex flex-col items-center bg-[#1E1E1E] overflow-y-auto py-8 gap-10">
          
          {/* Top Page (Partial) */}
          <div className="w-[85%] max-w-[800px] bg-white aspect-[1/1.4] rounded-md shadow-lg p-16 flex flex-col shrink-0 relative overflow-hidden">
             <div className="absolute top-0 w-full h-full opacity-5 pointer-events-none">
                <div className="w-[80%] h-6 bg-black mx-auto mt-24 mb-12"></div>
                <div className="w-full h-3 bg-black mb-4"></div>
                <div className="w-full h-3 bg-black mb-4"></div>
                <div className="w-3/4 h-3 bg-black mb-16"></div>
             </div>
             
             {/* Bottom half of the previous page visible */}
             <div className="mt-auto flex flex-col items-center pb-8 gap-8">
               <div className="w-[60%] h-8 bg-gray-100 rounded flex items-center justify-center">
                 <div className="w-1/2 h-3 bg-gray-300 rounded-sm"></div>
               </div>
               
               <div className="w-full flex flex-col gap-3 mt-4">
                 <div className="w-full h-2.5 bg-gray-200 rounded-sm"></div>
                 <div className="w-[40%] h-2.5 bg-gray-200 rounded-sm"></div>
               </div>
             </div>
          </div>

          {/* Active Page (Page 7) */}
          <div className="w-[85%] max-w-[800px] bg-white aspect-[1/1.4] rounded-md shadow-2xl p-16 flex flex-col shrink-0">
             
             {/* Abstract Text Lines */}
             <div className="w-full flex flex-col gap-3 mb-10">
               <div className="w-full h-2.5 bg-[#E5E5E5] rounded-sm"></div>
               <div className="w-full h-2.5 bg-[#E5E5E5] rounded-sm"></div>
               <div className="w-[90%] h-2.5 bg-[#E5E5E5] rounded-sm"></div>
             </div>
             
             <div className="w-full flex flex-col gap-3 mb-12">
               <div className="w-full h-2.5 bg-[#E5E5E5] rounded-sm"></div>
               <div className="w-[95%] h-2.5 bg-[#E5E5E5] rounded-sm"></div>
               <div className="w-full h-2.5 bg-[#E5E5E5] rounded-sm"></div>
               <div className="w-[80%] h-2.5 bg-[#E5E5E5] rounded-sm"></div>
             </div>

             {/* Highlighted text block */}
             <div className="w-full mb-12 flex justify-center">
               <div className="w-[90%] p-2 bg-[#FFF9C4]/80 rounded-sm border-l-2 border-[#FFD54F]">
                 <div className="w-full h-3 bg-[#D4C375] rounded-sm mb-2"></div>
                 <div className="w-[70%] h-3 bg-[#D4C375] rounded-sm"></div>
               </div>
             </div>

             {/* Subsection Heading */}
             <div className="w-[40%] h-4 bg-[#C0C0C0] mx-auto mb-6 rounded-sm"></div>

             {/* More abstract text */}
             <div className="w-full flex flex-col gap-3 mb-8">
               <div className="w-[92%] h-2.5 bg-[#E5E5E5] rounded-sm mx-auto"></div>
               <div className="w-[88%] h-2.5 bg-[#E5E5E5] rounded-sm mx-auto"></div>
               <div className="w-[95%] h-2.5 bg-[#E5E5E5] rounded-sm mx-auto"></div>
             </div>

             {/* Math Equation Block */}
             <div className="w-[60%] h-12 bg-gray-50 border border-gray-100 rounded-sm mx-auto flex items-center justify-center my-6">
                <div className="w-1/2 h-3 bg-gray-300 rounded-sm"></div>
             </div>

             <div className="w-full flex flex-col gap-3 mt-4">
               <div className="w-full h-2.5 bg-[#E5E5E5] rounded-sm"></div>
               <div className="w-[96%] h-2.5 bg-[#E5E5E5] rounded-sm"></div>
               <div className="w-[85%] h-2.5 bg-[#E5E5E5] rounded-sm"></div>
             </div>
             
             {/* Theorem Block */}
             <div className="w-full mt-10">
               <div className="w-[15%] h-3 bg-[#909090] rounded-sm mb-3"></div>
               <div className="w-full flex flex-col gap-2.5">
                 <div className="w-full h-2.5 bg-[#D5D5D5] rounded-sm"></div>
                 <div className="w-[90%] h-2.5 bg-[#D5D5D5] rounded-sm"></div>
               </div>
             </div>
          </div>
          
          {/* Bottom Page (Partial) */}
          <div className="w-[85%] max-w-[800px] bg-white aspect-[1/1.4] rounded-md shadow-lg p-16 flex flex-col shrink-0">
             <div className="w-[30%] h-3 bg-[#C0C0C0] mx-auto mb-10 rounded-sm"></div>
             <div className="w-full flex flex-col gap-3">
               <div className="w-full h-2.5 bg-[#E5E5E5] rounded-sm"></div>
               <div className="w-full h-2.5 bg-[#E5E5E5] rounded-sm"></div>
               <div className="w-[60%] h-2.5 bg-[#E5E5E5] rounded-sm"></div>
             </div>
          </div>

        </div>

        {/* Right Column (Highlights/Reference) */}
        <div className="w-72 lg:w-80 border-l border-[#2C2C2C] bg-[#252525] flex flex-col shrink-0 hidden sm:flex">
          
          <div className="p-4 pt-6 flex flex-col gap-6">
            
            {/* Segmented Control */}
            <div className="w-full bg-[#1A1A1A] rounded-full p-1 flex">
              <button className="flex-1 text-[12px] font-medium text-[#A0A0A0] py-1.5 rounded-full hover:text-white transition-colors">
                Highlights
              </button>
              <button className="flex-1 text-[12px] font-medium text-white bg-[#3C3C3C] py-1.5 rounded-full shadow-sm">
                Reference
              </button>
            </div>

            {/* Reference Card */}
            <div className="w-full bg-[#323232] rounded-xl p-4 border border-[#444] shadow-lg flex flex-col gap-3">
              <h4 className="text-[12px] font-semibold text-white">Theorem 1.3.1</h4>
              
              <div className="text-[13px] text-[#D4D4D4] leading-relaxed font-serif">
                Suppose <span className="font-mono text-[#9CDCFE] bg-[#1E1E1E] px-1 rounded">f : R² → R</span> has continuous partial derivatives. Then <span className="italic">f</span> is differentiable in <span className="font-mono text-[#9CDCFE] bg-[#1E1E1E] px-1 rounded">R²</span> with derivative at <span className="font-mono text-[#9CDCFE] bg-[#1E1E1E] px-1 rounded">a = (a,b)</span> given by 
                <div className="mt-2 text-center font-mono text-[#CE9178] bg-[#1E1E1E] p-2 rounded">
                  df(a) = (fₓ(a,b), fᵧ(a,b)).
                </div>
              </div>
            </div>

          </div>

        </div>

      </div>
    </div>
  );
}