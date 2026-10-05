
interface Notification {
    id: string
    text: string
    thisBoot?: boolean
    time?: number
}

export function setupNotifications(notificationsDivId: string) {

    const currentNotifications: Notification[] = [
        {
            id: "sample",
            text: "The wallmonitor was not able to update on the most recent update"
        }
    ]
    const notificationsDiv = document.getElementById(notificationsDivId)
    if(!notificationsDiv) return

    const badges = document.querySelectorAll<HTMLElement>(".badge")
    const updateBadges = () => {
        const count = notificationsDiv.querySelectorAll(".notification").length
        badges.forEach((badge) => {
            badge.textContent = String(count)
            badge.classList.toggle("show", count > 0)
        })
    }
    let notificationsShown = true
    const applyVisibility = () => {
        for (const notificationElement of notificationsDiv.children) {
            notificationElement.classList.toggle("show", notificationsShown)
        }
    }

    updateBadges()
    applyVisibility()
    new MutationObserver(() => {
        updateBadges()
        applyVisibility()
    }).observe(notificationsDiv, { childList: true })

    const bellButton = document.getElementById("bell")
    bellButton?.addEventListener("click", () => {
        notificationsShown = !notificationsShown
        const bellIcon = document.getElementById("bell-icon")
        if(bellIcon) bellIcon.classList.toggle("no-display", notificationsShown)
        const bellFull = document.getElementById("bell-full")
        if(bellFull) bellFull.classList.toggle("no-display", !notificationsShown)
        applyVisibility()
    })

    const dismissNotification = (id: string) => {
        const index = currentNotifications.findIndex((notification) => notification.id === id)
        if(index != -1) currentNotifications.splice(index, 1)
        document.getElementById(id)?.remove()
        void fetchDismissNotification(id)
    }

    // Leading call: otherwise the panel shows nothing for the first 10 seconds.
    const refreshNotifications = () => showNotifications(currentNotifications, notificationsDiv, dismissNotification)
    void refreshNotifications()
    setInterval(refreshNotifications, 10000)
}

async function showNotifications(currentNotifications: Notification[], notificationsDiv: HTMLElement, onDismiss: (id: string) => void) {
    for (const notification of await fetchNotifications()) {
        if(!currentNotifications.some((existing) => existing.id === notification.id))
            currentNotifications.push(notification)
    }

    const notificationElements = buildNotificationElements(currentNotifications, onDismiss)
    notificationsDiv.replaceChildren(...notificationElements)
}

async function fetchNotifications(): Promise<Notification[]> {
    try {
        const response = await fetch("/api/notifications")
        if(!response.ok) {
            console.log(`Failed to fetch notifications. Status: ${response.status}\n${await response.text()}`)
            return []
        }
        return await response.json() as Notification[]
    } catch (error) {
        console.log(`Unable to reach /api/notifications: ${error}`)
        return []
    }
}

function buildNotificationElements(notifications: Notification[], onDismiss: (id: string) => void) {
    return notifications.map((notification) => {
        const divElement = document.createElement('div')
        divElement.id = notification.id
        divElement.textContent = notification.text
        divElement.classList.add("notification")
        divElement.classList.add("warning")

        const closeButton = document.createElement('button')
        closeButton.classList.add("close-button")
        const xIcon = document.createElement('i')
        xIcon.className = "fa-solid fa-x"
        closeButton.appendChild(xIcon)
        closeButton.addEventListener("click", () => onDismiss(notification.id))

        divElement.appendChild(closeButton)

        return divElement
    })
}

async function fetchDismissNotification(id: string) {
    const url = `/api/notifications/dismiss/${id}`
    try {
        const response = await fetch(url, {method: 'POST'})
        if(!response.ok) {
            console.log(`Unable to dismiss notification ${id}. Status: ${response.status}\n${await response.text()}`)
        }
    } catch (error) {
        console.log(`Unable to reach ${url}: ${error}`)
        return []
    }
}

