
interface Notification {
    text: string
    thisBoot: boolean
    time: number
}

export function setupNotifications(notificationsDivId: string) {

    const currentNotifications: Notification[] = []
    const notificationsDiv = document.getElementById(notificationsDivId)
    if(!notificationsDiv) return

    setInterval(() => showNotifications(currentNotifications, notificationsDiv), 10000) // show new notifications every 10 seconds. TODO: Will the currentNotifications reference update properly? It should.

    // The badges are pure presentation of the notification list, so derive them
    // from the DOM and re-derive whenever showNotifications swaps the children.
    // Both get the same count; CSS decides which one is visible.
    const badges = document.querySelectorAll<HTMLElement>(".badge")
    const updateBadges = () => {
        const count = notificationsDiv.querySelectorAll(".notification").length
        badges.forEach((badge) => {
            badge.textContent = String(count)
            badge.classList.toggle("show", count > 0)
        })
    }
    updateBadges()
    new MutationObserver(updateBadges).observe(notificationsDiv, { childList: true })

}

async function showNotifications(currentNotifications: Notification[], notificationsDiv: HTMLElement) {
    const newNotifications = await fetchNotifications()
    currentNotifications = [...currentNotifications, ...newNotifications]

    const notificationElements = buildNotificationElements(currentNotifications)
    notificationsDiv.replaceChildren(...notificationElements)
}

async function fetchNotifications() {
    const response = await fetch("/api/notifications")
    if(!response.ok) {
        console.log(`Failed to fetch notifications. Status: ${response.status}\n${await response.text()}`)
        return []
    }
    const notifications = await response.json() as Notification[]
    return notifications
}

function buildNotificationElements(notifications: Notification[]) {
    return notifications.map((notification) => {
        const divElement = document.createElement('div')
        divElement.textContent = notification.text
        divElement.classList.add("notification")
        divElement.classList.add("warning")
        return divElement
    })
}

