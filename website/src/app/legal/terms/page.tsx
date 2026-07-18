export const metadata = {
  title: "Terms of Use | Cauchy",
  description: "Cauchy's terms of use.",
};

export default function TermsPage() {
  return (
    <div className="w-full max-w-3xl mx-auto px-6 py-24 sm:py-32">
      <h1 className="text-[40px] sm:text-[56px] font-medium tracking-[-0.03em] leading-[1.1] text-primary mb-8">
        Terms of Use
      </h1>
      
      <div className="max-w-none text-[16px] leading-relaxed text-secondary [&>h2]:text-2xl [&>h2]:mt-12 [&>h2]:mb-4 [&>h2]:text-primary [&>h2]:font-medium [&>p]:mb-4">
        <p className="text-secondary text-lg mb-8">
          Last updated: July 18, 2026
        </p>

        <h2 className="text-2xl mt-12 mb-4 text-primary">1. Open Source Software</h2>
        <p className="text-secondary">
          Cauchy is open-source software provided free of charge. The application is distributed under the terms of its open-source license (see the repository for the specific license terms).
        </p>

        <h2 className="text-2xl mt-12 mb-4 text-primary">2. No Warranties</h2>
        <p className="text-secondary">
          THE SOFTWARE IS PROVIDED &quot;AS IS&quot;, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        </p>

        <h2 className="text-2xl mt-12 mb-4 text-primary">3. API Usage and Costs</h2>
        <p className="text-secondary">
          Cauchy allows you to bring your own API keys (e.g., Gemini) or authenticate with third-party command-line interfaces (e.g., Claude Code, Codex). You are solely responsible for any costs, usage limits, or account restrictions incurred by your use of these services.
        </p>
        <p className="text-secondary mt-4">
          Cauchy has no affiliation with these third-party services. Your use of those services is governed by your agreements directly with those providers.
        </p>

        <h2 className="text-2xl mt-12 mb-4 text-primary">4. Unsandboxed Execution</h2>
        <p className="text-secondary">
          By installing and using Cauchy, you acknowledge that the application runs unsandboxed. This is necessary to spawn local CLI processes but means the application has the same access rights to your system as your user account.
        </p>

        <h2 className="text-2xl mt-12 mb-4 text-primary">5. Changes to Terms</h2>
        <p className="text-secondary">
          We reserve the right to update these terms at any time. Changes will be reflected on this page.
        </p>
      </div>
    </div>
  );
}
