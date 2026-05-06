module Helpdesk
  class MenuPresenter
    def self.menu
      [
        "",
        "Interactive Menu",
        "d) Dashboard",
        "l) List tickets",
        "s) Show ticket",
        "n) New ticket",
        "f) Search tickets",
        "w) Who am I",
        "h) Help",
        "q) Exit menu",
        "Shortcuts: d l s n f w h q"
      ].join("\n")
    end

    def self.shortcuts
      "Shortcuts: d dashboard, l list, s show, n new, f search, w whoami, q quit"
    end
  end
end
