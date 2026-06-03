// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

// 1. DEFINE HOOKS FIRST
let Hooks = {};

// Hook 1: Manages auto-scrolling the terminal output
Hooks.ScrollToBottom = {
  mounted() {
    this.scrollToBottom();
  },
  updated() {
    this.scrollToBottom();
  },
  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight;
  },
};

// Hook 2: Manages the input field (Focus, Keystrokes, History, Validation, & Tab Cycling)
Hooks.TerminalInput = {
  mounted() {
    // State Variables
    this.history = [];
    this.historyIndex = -1;
    this.temporaryInput = "";

    // Tab Cycling Variables
    this.tabMatches = [];
    this.tabIndex = -1;

    this.validCommands = [
      "help",
      "ls",
      "cat",
      "clear",
      "sysinfo",
      "tree",
      "sudo",
      "open",
      "whoami",
      "history",
    ];

    // Global focus lock
    this.focusHandler = (e) => {
      if (window.getSelection().toString() === "") {
        this.el.focus();
      }
    };
    document.addEventListener("click", this.focusHandler);

    // Syntax Colorizer
    this.colorize = () => {
      const val = this.el.value.trim();
      const baseCmd = val.split(" ")[0];

      this.el.classList.remove(
        "text-[#50fa7b]",
        "text-[#ff5555]",
        "text-[#f8f8f2]",
      );

      if (val === "") {
        this.el.classList.add("text-[#f8f8f2]");
      } else if (this.validCommands.includes(baseCmd)) {
        this.el.classList.add("text-[#50fa7b]");
      } else {
        this.el.classList.add("text-[#ff5555]");
      }
    };

    // Reset Tab cycle if user types manually
    this.el.addEventListener("input", (e) => {
      this.tabMatches = [];
      this.colorize();
    });

    // Keystroke Interceptor
    this.el.addEventListener("keydown", (e) => {
      if (e.key === "Tab") {
        e.preventDefault();

        if (this.tabMatches.length > 0) {
          // If we already have matches cached, cycle to the next one locally
          this.tabIndex = (this.tabIndex + 1) % this.tabMatches.length;
          this.el.value = this.tabMatches[this.tabIndex];
          this.colorize();
        } else {
          // Otherwise, ask Elixir to fetch the matches
          this.pushEvent("autocomplete", { value: this.el.value });
        }
      } else {
        // If ANY key other than Tab or modifiers is pressed, clear the cycle cache
        if (["Shift", "Control", "Alt", "Meta"].indexOf(e.key) === -1) {
          this.tabMatches = [];
          this.tabIndex = -1;
        }

        if (e.key === "Enter") {
          e.preventDefault();
          const commandText = this.el.value.trim();

          if (commandText !== "") {
            if (
              this.history.length === 0 ||
              this.history[this.history.length - 1] !== commandText
            ) {
              this.history.push(commandText);
            }
          }

          this.historyIndex = this.history.length;
          this.temporaryInput = "";

          this.pushEvent("execute", { command: this.el.value });
          this.el.value = "";
          this.colorize();
        } else if (e.key === "ArrowUp") {
          e.preventDefault();
          if (this.history.length === 0) return;

          if (this.historyIndex === this.history.length) {
            this.temporaryInput = this.el.value;
          }
          if (this.historyIndex > 0) {
            this.historyIndex--;
            this.el.value = this.history[this.historyIndex];
            this.colorize();
          }
        } else if (e.key === "ArrowDown") {
          e.preventDefault();
          if (this.history.length === 0) return;

          if (this.historyIndex < this.history.length - 1) {
            this.historyIndex++;
            this.el.value = this.history[this.historyIndex];
            this.colorize();
          } else if (this.historyIndex === this.history.length - 1) {
            this.historyIndex++;
            this.el.value = this.temporaryInput;
            this.colorize();
          }
        }
      }
    });

    // Catch the array of matches from Elixir
    this.handleEvent("update_autocomplete", (payload) => {
      if (payload.matches && payload.matches.length > 0) {
        this.tabMatches = payload.matches;
        this.tabIndex = 0;
        this.el.value = this.tabMatches[this.tabIndex];
        this.colorize();
      }
    });
  },

  destroyed() {
    document.removeEventListener("click", this.focusHandler);
  },
};

// Hook 3: Triggers Highlight.js on any code blocks rendered inside the terminal
Hooks.SyntaxHighlight = {
  mounted() {
    this.el.querySelectorAll("pre code").forEach((block) => {
      hljs.highlightElement(block);
    });
  },
  updated() {
    this.el.querySelectorAll("pre code").forEach((block) => {
      hljs.highlightElement(block);
    });
  },
};

// Hook 4: Makes modal windows draggable via their title bar
Hooks.DraggableWindow = {
  mounted() {
    // Find the title bar to act as the handle
    const handle = this.el.querySelector("#window-handle");
    if (!handle) return;

    let isDragging = false;
    let currentX;
    let currentY;
    let initialX;
    let initialY;

    // Default starting position offsets (starts at 0,0 relative to its CSS position)
    let xOffset = 0;
    let yOffset = 0;

    const dragStart = (e) => {
      // Don't start dragging if they clicked the 'X' button
      if (e.target.tagName.toLowerCase() === "button") return;

      initialX = e.clientX - xOffset;
      initialY = e.clientY - yOffset;

      if (e.target === handle || handle.contains(e.target)) {
        isDragging = true;
      }
    };

    const dragEnd = () => {
      initialX = currentX;
      initialY = currentY;
      isDragging = false;
    };

    const drag = (e) => {
      if (isDragging) {
        e.preventDefault();
        currentX = e.clientX - initialX;
        currentY = e.clientY - initialY;

        xOffset = currentX;
        yOffset = currentY;

        // Use translate3d for hardware-accelerated smooth rendering
        this.el.style.transform = `translate3d(${currentX}px, ${currentY}px, 0)`;
      }
    };

    // Attach to document so you don't lose the drag if your mouse moves too fast
    document.addEventListener("mousedown", dragStart, false);
    document.addEventListener("mouseup", dragEnd, false);
    document.addEventListener("mousemove", drag, false);

    // Store cleanup function
    this.cleanup = () => {
      document.removeEventListener("mousedown", dragStart, false);
      document.removeEventListener("mouseup", dragEnd, false);
      document.removeEventListener("mousemove", drag, false);
    };
  },

  destroyed() {
    if (this.cleanup) this.cleanup();
  },
};

// Hook to handle markdown styling, syntax highlighting, and secure links
Hooks.SyntaxHighlight = {
  mounted() {
    this.secureLinks();
  },
  updated() {
    this.secureLinks();
  },
  secureLinks() {
    // Find all anchor tags within this specific bat output/window
    const links = this.el.querySelectorAll("a");

    links.forEach((link) => {
      // Force them to open in a new tab securely
      link.setAttribute("target", "_blank");
      link.setAttribute("rel", "noopener noreferrer");
    });
  },
};

// 2. INITIALIZE SOCKET WITH HOOKS ALREADY DEFINED
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks, // Now this knows what 'Hooks' is!
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation
window.liveSocket = liveSocket;
