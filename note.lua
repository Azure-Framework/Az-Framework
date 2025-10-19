-- This script will display a permanent message on the screen for all players.

-- Create a loop that runs continuously without blocking the main game thread.
CreateThread(function()
    while true do
        Wait(0) -- Wait for the next frame.

        -- Set the text properties.
        SetTextFont(4) -- Font 4 is a common, clean font.
        SetTextScale(0.35, 0.35) -- Adjusted size for better readability and to prevent being huge.
        SetTextColour(255, 255, 255, 255) -- White text.
        SetTextDropshadow(0, 0, 0, 0, 255) -- Add a subtle dropshadow.
        SetTextEdge(1, 0, 0, 0, 255) -- Add a black outline for readability.
        SetTextOutline()
        
        -- Enable horizontal centering for the text.
        SetTextCentre(true)

        -- Set text wrap boundaries to prevent the message from running off the screen.
        SetTextWrap(0.1, 0.9)

        SetTextEntry("STRING") -- Prepare to draw text.

        -- Combine the message into a single string with multiple newline characters (~n~)
        -- to ensure it wraps correctly and stays centered, preventing any cut-off.
        local message = "This is a framework testing / development server.~n~If there are issues or small problems, please let us know.~n~Enjoy!"
        AddTextComponentString(message)
        
        -- Draw the text at the top-center of the screen.
        -- The position is based on a 0.0 to 1.0 scale from the top-left corner.
        -- The entire block of text will now be correctly centered.
        DrawText(0.5, 0.05)
    end
end)
