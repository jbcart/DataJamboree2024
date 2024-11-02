using HTTP, Gumbo, Cascadia # for static webscraping
using WebDriver # for remote control of a website

# Start Webdriver
capabilities = Capabilities("chrome")

wd = RemoteWebDriver(
  capabilities,
  host = "localhost",
  port = 65396 # replace this with the correct port
)

session = Session(wd)

# navigate to the webpage
url = "https://olympics.com/en/paris-2024/athletes/artistic-gymnastics"
navigate!(session, url)

# Click Cookies button
# May use a location strategy from "css selector", "link text",
# "partial link text", "tag name" or "xpath".
cookies_button = Element(session, "css selector", "#onetrust-accept-btn-handler")
click!(cookies_button)

# Scrape rendered html
html = parsehtml(source(session))
body = html.root[2]

# HTMLElements
fieldnames(typeof(body))
body.attributes
body[1]
body[10][2]

# find matches for with css selector
matches = eachmatch(Selector("span.competitor-long-name"), body)
length(matches)

# extract node text
nodeText(matches[1])

# Extract text from vector of html element
athlete_names = Vector{String}()
for item ∈ matches
  push!(athlete_names, nodeText(item))
end

# move to next page button
next_button = Element(session, "css selector", "div.mirs-pagination-right > button:nth-child(2)")
moveto!(next_button)

# move to next page box
box = Element(session, "css selector", "div.mirs-pagination-right")
moveto!(box)

# click to the next page
click!(next_button)

function get_athlete_names(sport, session, sleep_time=1)
  url = "https://olympics.com/en/paris-2024/athletes/" * sport
  navigate!(session, url)
  sleep(sleep_time)

  cookies_button = Element(session, "css selector", "#onetrust-accept-btn-handler")
  try 
    click!(cookies_button)
  catch
  end
  println("Webpage Loaded")

  athlete_names = Vector{String}()
  box = Element(session, "css selector", "div.mirs-pagination-right")
  sleep(sleep_time)
  for _ ∈ 1:3
    moveto!(box)
    sleep(sleep_time)
  end
  while true
    html = parsehtml(source(session))
    matches = eachmatch(Selector("span.competitor-long-name"), html.root[2])
  
    for item ∈ matches
        push!(athlete_names, nodeText(item))
    end

    next_button = Element(session, "css selector", "div.mirs-pagination-right > button:nth-child(2)")
    if isenabled(next_button)
      click!(next_button)
      sleep(sleep_time)
    else 
      break 
    end
  end
  
  unique!(athlete_names)
end


# Vector of all sports pages we want to scrape
sports = ["artistic-gymnastics", "football", "swimming", "volleyball", "basketball", "athletics"]

# Loop through and scrape all sports pages
n_athletes = Vector{Int}()
athlete_name = Vector{String}()
for s ∈ sports
  out = get_athlete_names(s, session)
  append!(athlete_name, out)
  push!(n_athletes, length(out))
end

# save into a DataFrame
df = DataFrame(athlete_name=athlete_name,
  sport = reduce(vcat, fill.(sports, n_athletes)),
  wiki_name = "",
  month = 0
)

delete!(session)