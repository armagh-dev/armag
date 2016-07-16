#!/bin/bash
set -e
set -x

ruby --version
mongod --version
cd /workspace
gem install bundler --no-doc
bundle install
rake ci_vm