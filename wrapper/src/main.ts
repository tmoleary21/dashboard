import "@fortawesome/fontawesome-free/css/all.min.css"

const wrappedSite = import.meta.env.VITE_WRAPPED_SITE || "about:blank"

document.addEventListener("DOMContentLoaded", () => {

    const wrapperIframe = document.getElementById("wrapper") as HTMLIFrameElement | null
    const setSrc = (src: string) => {
        if(wrapperIframe) wrapperIframe.src = src
    }
    setSrc(wrappedSite)

    const menuButton = document.getElementById("menu")
    const menuSelect = document.getElementById("menu-select")
    const optionsWrapper = document.getElementById("menu-options")
    const options = Array.from(document.querySelectorAll<HTMLElement>(".option"))

    // --i / --n drive the staggered transition delays in index.html.
    options.forEach((option, i) => option.style.setProperty("--i", String(i)))
    menuSelect?.style.setProperty("--n", String(options.length))

    let menuOpen = false
    let closeMenuTimeout = -1
    const setMenuOpen = (open: boolean) => {
        if(closeMenuTimeout != -1) {
            clearTimeout(closeMenuTimeout)
            closeMenuTimeout = -1
        }
        if(!menuSelect || !optionsWrapper) return
        menuOpen = open
        menuSelect.classList.toggle("open", open)
        // Animating to an explicit pixel height is what lets the dark
        // background slide up/down instead of snapping.
        optionsWrapper.style.height = open ? `${optionsWrapper.scrollHeight}px` : "0px"
        menuButton?.setAttribute("aria-expanded", String(open))
        if(open) {
            closeMenuTimeout = setTimeout(() => setMenuOpen(false), 5000)
        }
    }
    const toggleMenu = () => setMenuOpen(!menuOpen)

    const backButton = document.getElementById("back")
    backButton?.addEventListener("click", () => history.back())
    
    const homeButton = document.getElementById("home")
    homeButton?.addEventListener("click", () => setSrc(wrappedSite))

    menuButton?.addEventListener("click", toggleMenu)

    const refreshButton = document.getElementById("refresh")
    refreshButton?.addEventListener("click", () => location.reload())

    // Collapse after picking something.
    options.forEach((option) => option.addEventListener("click", () => setMenuOpen(false)))

})
