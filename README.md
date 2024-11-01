---
title: Webscraping in Julia
author: Brandon Carter
date: November 2nd, 2024
---

# Data Jamboree 2024
Julia code for the ASA computing section mini-symposium data jamboree. 

## Intro
Full disclosure, this was my first time webscrapping in `Julia`, so I'm sure that my solution could be a little more elegant, though webscrapping concepts are pretty consistent across languages.
In this demo - we deal with two different types of websites, dynamic and static.
For dynamic sites we need a web driver in order to interact with the website through code.
This allows the different scripts on the website to run after which we can then scrap the compiled html. 

In `Julia` we have two options of packages: `Blink` which is a wrapper for `Electron` and can communicate to the browser through `JavaScript`.
I was not able to get the [olympics](https://olympics.com/en/paris-2024/athletes/artistic-gymnastics) website to load in Blink (other websites did load) so I did not spend too much time messing with with the package.
Additionally, for `Blink` you are pass `JavaScript` code which is a little more complicated than using the wrapper functions from a web driver package (though may be easier if you are familiar with `JavaScript`).

The second option is `WebDriver`, a wrapper for `Selenium` and should be very familiar to those who have used the `webdriver` package in `Python`. [^1] 
This is the package that I use in the demo. 
[The documentation](https://nosferican.github.io/WebDriver.jl/dev/) is rather sparse, but there is a nice tutorial for web automation using `WebDriver` in julia [here](https://www.youtube.com/watch?v=KWYNlIOxQpo).
While `WebDriver` accomplishes everything we need for this demo, the package is more lightweight than the correpsonding `Python` package.
Using the `WebDriver` package requires a web driver application and following the linked tutorial, I also use `chromedriver`, but you can select a different web driver if you prefer.

For static websites we use the `HTTP` package to scrap the html, `Gumbo` to parse the html into a structured object which can then be easily indexed by the tree structure of the html code.
Lastly, the `Cascadia` package can extract elements from the html using css selectors.
[Here](https://www.youtube.com/watch?v=qv7M5oBZPWE) is a tutorial for these three packages. 

[^1]: The is also another `WebDriver` package out there which is deprecated. Some tutorials on YouTube use this older package which has different functions.

## Getting Started
In the chunk below we create a virtual environment with `Pkg.activate(@__DIR__)` and install all the packages required with `Pkg.instantiate()`.
```julia
using Pkg

Pkg.activate(@__DIR__)
Pkg.instantiate()
```

```julia
using HTTP, Gumbo, Cascadia # for static webscraping
using WebDriver, DefaultApplication # for remote control of a website
using ProgressBars
using DataFrames, CSV, PrettyTables
using Plots, StatsPlots
using StatsBase
```

## Web Driver
First we need to set up our webdriver. We can open the webdriver with `DefaultApplication` or go to the terminal and start `chromdriver`.
When we start `chromedriver`, it will specify which port the application is using. We will need this to start our web driver session. 

```julia
DefaultApplication.open("chromedriver") 
```

The `RemoteWebDriver` function requires three arguments: capabilities which specifies which browser we are using, the host and the port which is printed to the terminal when we start up `chromedriver`. 
(I'm sure you could fully automate this by starting up chromedriver on a specified port, but this works for here)

```julia
capabilities = Capabilities("chrome")

wd = RemoteWebDriver(
  capabilities,
  host = "localhost",
  port = 55130 # replace this with the correct port
)

session = Session(wd)
```

### Navigating through and scraping the webpage
Before we create a function, we will figure out how to navigate through the webpage through the webdriver.
This essentially boils down to inspecting the website to find the appropriate tag for the buttons that we want to click, using the tag (css selector, xpath, etc.) to find the element through code, then clicking the button with code. For each page that we are on, we can scrape the source html with the parse `parsehtml` function from `Gumbo` and then extract the elements that we want using css selectors and the `Cascadia` package. 

Lets start with [artistic gymnastics](https://olympics.com/en/paris-2024/athletes/artistic-gymnastics).
With our session already up, we can navigate to the url with `navigate!()`.

```julia 
url = "https://olympics.com/en/paris-2024/athletes/artistic-gymnastics"
navigate!(session, url)
```
The accept cookies pops up first:
![](figures/screenshot_1.png)
We can inspect the element (right click and select inspect on Mac) to find a tag for the accept cookies button:
![](figures/screenshot_2.png)
and can see the the css selector is `#onetrust-accept-btn-handler`. 
We find this element with the `Element` function from `WebDriver` and 'click' the element with `click!()`.
```julia
cookies_button = Element(session, "css selector", "#onetrust-accept-btn-handler")
click!(cookies_button)
```
Note that here we use the css selector, but we can use other tags such as an xpath to identify the element.
Later on when we use `Cascadia`, we can only use css selectors. 

Now we are at the page with the athletes listed.
Inspecting the name portion of the table we can find the appropriate tag to identify the athlete names.
![](figures/screenshot_3.png)
We will now switch to `Gumbo` to parse the rendered html and Cascadia to scrape all the athlete names:
```julia
html = parsehtml(source(session))
body = html.root[2]
matches = eachmatch(Selector("span.competitor-long-name"), body)
```
We source the rendered html from our session and parse with `Gumbo`. 
The body of the html is the second element of the root of the parsed html (the header is the first element of the root). 
The `eachmatch` function from base `Julia` works with the `HTMLElement{:HTML}` class by wrapping a css selector with the `Selector` function and returns each match html element in a vector.
A single match will return a vector of length 1. 
We selected the html element that just contains the name of the athlete, so all that is left to do is extract the text which we can do with the function `nodeText()`.
```julia
athlete_names = Vector{String}()
for item ∈ matches
  push!(athlete_names, nodeText(item))
end
```
This only gives us the first 50 athletes, we need to navigate to the next page button and click it to bring up the next page of athletes.
Following the same process as before we inspect the element to find the appropriate tag. Find the element with our code and click it.
```julia
next_button = Element(session, "css selector", "div.mirs-pagination-right > button:nth-child(2)")
click!(next_button)
```

Now we can put these elements together to create a function to scrape all the athletes from a single sport.
The urls are consistent so we can append the base url with the sport name
```julia
url = "https://olympics.com/en/paris-2024/athletes/" * sport
```
After we navigate to the webpage, we want the the system to sleep so the webpage renders completely before we try to click any buttons (or scrape data).
```julia
navigate!(session, url)
  sleep(sleep_time)
```
We only need to click the cookies button once, so we throw it into a try-catch statement so our function doesn't break when the cookies button doesn't appear. 
```julia
  try 
    click!(cookies_button)
  catch
  end
```
In order to move to the next page button, we can use the `moveto!` function.
Moving to the next page button didn't work very well so I found the tag for the box around the next page buttons which seemed to work better. 
We need to move to the button in the webdriver so that it is in view of the driver otherwise the click command won't work.
A single execution of `moveto!` didn't always navigate to the box, so we throw it into a for loop to help the web driver really navigate to the button. 
```julia
box = Element(session, "css selector", "div.mirs-pagination-right")
  sleep(sleep_time)
  for _ ∈ 1:3
    moveto!(box)
    sleep(sleep_time)
  end
```
Lastly, we want to keep navigating and scraping athlete names as long as the next page button is enabled. We will break out of our while loop after we scrape the final page and check with `isenabled(next_button)` returns `false`. 

```julia
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
```

```julia; results = "hidden"
df = CSV.read("athlete_df.csv", DataFrame)
```


```julia
df[:,:sport_type] = ifelse.(df.sport .∈ (["football", "volleyball", "basketball"],), "team", "individual")
filter!(:month => !=(0), df)

ind = combine(groupby(df[df.sport_type .== "individual",:], :month), nrow => :count)
team = combine(groupby(df[df.sport_type .== "team",:], :month), nrow => :count)

ind.rel_freq = ind.count ./ sum(ind.count)
team.rel_freq = team.count ./ sum(team.count)

both = innerjoin(ind, team, on=:month, makeunique=true)
select!(both,[:month, :rel_freq, :rel_freq_1])
rename!(both, ["Month", "Individual", "Team"])

pretty_table(both, backend=Val(:markdown), formatters=ft_printf("%5.3f", [2,3]))
```
| **Month**<br>`Int64` | **Individual**<br>`Float64` | **Team**<br>`Float64` |
|---------------------:|----------------------------:|----------------------:|
| 1                    | 0.100                       | 0.084                 |
| 2                    | 0.079                       | 0.091                 |
| 3                    | 0.085                       | 0.072                 |
| 4                    | 0.079                       | 0.081                 |
| 5                    | 0.090                       | 0.089                 |
| 6                    | 0.082                       | 0.089                 |
| 7                    | 0.080                       | 0.108                 |
| 8                    | 0.085                       | 0.086                 |
| 9                    | 0.088                       | 0.072                 |
| 10                   | 0.082                       | 0.076                 |
| 11                   | 0.075                       | 0.084                 |
| 12                   | 0.074                       | 0.069                 |


```julia
p1 = bar(ind.month, ind.rel_freq, yaxis="Relative Frequency", legend=false, title="Individual")
p2 = bar(team.month, team.rel_freq, legend=false, title="Team")
plot(p1,p2, xaxis="Month", layout=(1,2))
```

![](figures/fig1.png)