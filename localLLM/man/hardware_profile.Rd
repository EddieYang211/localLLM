% Generated manually; sync with R/capacity.R
\name{hardware_profile}
\alias{hardware_profile}
\title{Inspect detected hardware resources}
\usage{
hardware_profile(refresh = FALSE)
}
\arguments{
\item{refresh}{When \code{TRUE}, forces a fresh probe instead of returning the cached profile.}
}
\value{
A list describing the operating system, CPU cores, total RAM (bytes), GPU information and detection timestamp.
}
\description{
Returns the cached system profile recorded by localLLM when the package was attached. The probe captures approximate CPU, RAM, and GPU capacity so that safety warnings can estimate whether a model fits the device.
}
\examples{
if (interactive()) {
  hardware_profile()
}
}
