import "@fortawesome/fontawesome-free/css/all.min.css"

const wrappedSite = import.meta.env.VITE_WRAPPED_SITE || "about:blank"

document.addEventListener("DOMContentLoaded", () => {

    const wrapperIframe = document.getElementById("wrapper") as HTMLIFrameElement | null
    const setSrc = (src: string) => {
        if(wrapperIframe) wrapperIframe.src = src
    }
    setSrc(wrappedSite)

    const backButton = document.getElementById("back")
    backButton?.addEventListener("click", () => history.back())
    
    const homeButton = document.getElementById("home")
    homeButton?.addEventListener("click", () => setSrc(wrappedSite))

})
