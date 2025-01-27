# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# OpenStudio base image (https://hub.docker.com/r/nrel/openstudio/tags)
FROM nrel/openstudio:3.6.1 as os-base

LABEL maintainer="Henry (Ry) Horsey henry.horsey@nrel.gov"

# Copy the Gemfile from the ComStock Repo into the container
COPY /resources/Gemfile /var/oscli/

# Install custom gems
ENV BUNDLE_WITHOUT=
RUN bundle config set git.allow_insecure true \
    && bundle config set path /var/oscli/gems/ \
    && bundle config set without 'native_ext' \
    && bundle install --gemfile /var/oscli/Gemfile \
    && openstudio --verbose --bundle /var/oscli/Gemfile --bundle_path /var/oscli/gems --bundle_without native_ext  gem_list \
    && bundle config

# Remove blobs from gems installed through git
RUN rm -rf /var/oscli/gems/ruby/2.7.0/bundler/gems/**/.git \
    /var/oscli/gems/ruby/2.7.0/bundler/gems/**/test \
    /var/oscli/gems/ruby/2.7.0/cache/bundler

# Create a slimmer container without development libraries leftover by OpenStudio
FROM ubuntu:20.04 AS os-comstock

ARG OPENSTUDIO_VERSION=3.6.1
ARG OPENSTUDIO_VERSION_EXT=""
ENV OPENSTUDIO_VERSION=3.6.1

# copy executable and energyplus from install
COPY --from=os-base /usr/local/openstudio-${OPENSTUDIO_VERSION}${OPENSTUDIO_VERSION_EXT}/ /usr/local/openstudio-${OPENSTUDIO_VERSION}${OPENSTUDIO_VERSION_EXT}/
COPY --from=os-base /var/oscli/ /var/oscli/

RUN apt-get update && apt-get install -y --no-install-recommends \
            libdbus-glib-1-2 \
            libglu1 \
            libssl-dev \
            libpng-dev \
            libgdbm-dev \
            libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# link executable from /usr/local/bin
RUN ln -s /usr/local/openstudio-${OPENSTUDIO_VERSION}${OPENSTUDIO_VERSION_EXT}/bin/openstudio /usr/local/bin/openstudio
ENV LC_ALL=C

VOLUME /var/simdata/openstudio
WORKDIR /var/simdata/openstudio

# Ensure that openstudio can load the custom gems
RUN openstudio --verbose --bundle /var/oscli/Gemfile --bundle_path /var/oscli/gems --bundle_without native_ext gem_list
