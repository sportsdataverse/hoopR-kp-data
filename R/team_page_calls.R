library(tidyverse)
library(rvest)
library(xml2)
library(dplyr)
library(stringr)
library(tidyr)
library(stringr)
library(xml2)
source("R/pull_team_page.R")

yr <- 2021

gather_team_pages(year = yr, fp = "data")

