import type { PropsWithChildren } from "react"
import { Box } from "@mui/material"

export default function DashboardGrid() {

    const randomizedGridItems = []
    for(let i = 0; i < 64; i++) {
        randomizedGridItems.push(<GridItem size={i % 4 + 1} key={i}/>)
    }

    const desiredColumnWidth = '12.5%'
    const minimumColumnWidth = '100px'
    const columnWidth = `minmax(${minimumColumnWidth}, ${desiredColumnWidth})`

    const sx = {
        backgroundColor: "#2F2F2F",
        padding: '8px',

        // Grid layout
        display: "grid",
        gridTemplateColumns: `repeat(auto-fill, ${columnWidth})`,
        gridAutoFlow: 'dense', // If a large item leaves a gap on the line, the grid will pull smaller items out of their DOM order to fill the space
        gap: '4px'
    }

    return (
        <Box sx={sx}>
            {randomizedGridItems}
        </Box>
    )
}

type GridItemProps = PropsWithChildren<{
    size: number
}>

function GridItem({ children, size }: GridItemProps) {
    return (
        <Box sx={{ border: "1px solid #20C20E", height: "20px", gridColumn: `span ${size}`, gridRow: 'span 2' }}>
            {children}
        </Box>
    )
}