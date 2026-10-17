import { CopyCommand } from "@/components/CopyCommand";
import { PanelPreview } from "@/components/PanelPreview";
import { StatusShowcase } from "@/components/StatusShowcase";

const installCommand = "brew install --cask ikramhasan/tap/vibecheck";
const repo = "https://github.com/ikramhasan/vibecheck";

const features = [
  {
    title: "Nothing to install",
    body: "vibecheck reads the session files Claude Code, Codex and pi already write. Start an agent and it shows up.",
  },
  {
    title: "Knows when it's your turn",
    body: "Questions and plan approvals jump to the top, and you get a nudge when an agent finishes.",
  },
  {
    title: "Plan usage at a glance",
    body: "5-hour, weekly and monthly limits for Claude, Codex and Kiro, read from the sign-in each agent already has.",
  },
  {
    title: "Sessions on other machines",
    body: "Add an ssh host and its sessions stream in beside your local ones over a single connection.",
  },
  {
    title: "Dev servers and diffs",
    body: "See which servers a session started, stop them, and check what it changed without leaving your editor.",
  },
  {
    title: "Read-only by design",
    body: "It never writes, moves or locks an agent's files, and never refreshes its tokens. It only watches.",
  },
];

export default function Home() {
  return (
    <>
      <header className="nav">
        <a className="brand" href="/">
          <img src="/icon.png" width={28} height={28} alt="" />
          vibecheck
        </a>
        <a className="nav-link" href={repo}>
          <GitHubLogo />
          GitHub
        </a>
      </header>

      <main>
        <section className="hero">
          <h1>Every coding agent, at the edge of your screen.</h1>
          <p className="lede">
            vibecheck is a native macOS panel that tucks against the side of your display. Hover it to see which
            agents are working, which are waiting on you and how much of your plan is left.
          </p>
          <CopyCommand command={installCommand} />
          <p className="requirements">Free · macOS 26 on Apple Silicon</p>
        </section>

        <section className="preview" aria-label="Panel preview">
          <PanelPreview />
        </section>

        <section className="intro" aria-label="Intro video">
          <video src="/intro.mp4" poster="/intro-poster.jpg" width={1920} height={1080} controls playsInline preload="none" />
        </section>

        <section className="statuses" aria-labelledby="statuses-title">
          <h2 id="statuses-title">One orb per session</h2>
          <p className="section-lede">
            The tab stays a few pixels wide. Each orb tells you what its agent is up to, in the style you pick.
          </p>
          <StatusShowcase />
        </section>

        <section className="features" aria-label="Features">
          {features.map((feature) => (
            <article key={feature.title}>
              <h3>{feature.title}</h3>
              <p>{feature.body}</p>
            </article>
          ))}
        </section>

        <section className="install" aria-labelledby="install-title">
          <img src="/icon.png" width={72} height={72} alt="" />
          <h2 id="install-title">Check the vibe.</h2>
          <CopyCommand command={installCommand} />
          <p className="requirements">Installs through Homebrew and updates itself.</p>
        </section>
      </main>

      <footer className="footer">
        <p>
          Orbs ported from <a href="https://github.com/yogesharc/thinking-orbs">thinking-orbs</a>. Usage clients and
          agent icons from <a href="https://github.com/steipete/CodexBar">CodexBar</a> and{" "}
          <a href="https://github.com/lobehub/lobe-icons">lobe-icons</a>. All MIT.
        </p>
        <a className="footer-github" href={repo}>
          <GitHubLogo />
          Source on GitHub
        </a>
      </footer>
    </>
  );
}

function GitHubLogo() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M12 .5C5.65.5.5 5.65.5 12a11.5 11.5 0 0 0 7.86 10.92c.58.1.79-.25.79-.56v-2c-3.2.7-3.88-1.37-3.88-1.37-.52-1.33-1.28-1.69-1.28-1.69-1.05-.71.08-.7.08-.7 1.16.08 1.77 1.19 1.77 1.19 1.03 1.77 2.7 1.26 3.36.96.1-.75.4-1.26.73-1.55-2.55-.29-5.24-1.28-5.24-5.69 0-1.26.45-2.28 1.19-3.09-.12-.29-.52-1.46.11-3.05 0 0 .97-.31 3.17 1.18a11 11 0 0 1 5.77 0c2.2-1.49 3.17-1.18 3.17-1.18.63 1.59.23 2.76.11 3.05.74.81 1.19 1.83 1.19 3.09 0 4.42-2.69 5.39-5.26 5.68.41.36.78 1.06.78 2.14v3.17c0 .31.21.67.8.56A11.5 11.5 0 0 0 23.5 12C23.5 5.65 18.35.5 12 .5Z" />
    </svg>
  );
}
