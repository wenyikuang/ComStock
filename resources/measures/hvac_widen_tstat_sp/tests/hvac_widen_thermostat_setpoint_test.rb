# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2018, Alliance for Sustainable Energy, LLC.
# All rights reserved.
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# (1) Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# (2) Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# (3) Neither the name of the copyright holder nor the names of any contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission from the respective party.
#
# (4) Other than as required in clauses (1) and (2), distributions in any form
# of modifications or other derivative works may not use the "OpenStudio"
# trademark, "OS", "os", or any other confusingly similar designation without
# specific prior written permission from Alliance for Sustainable Energy, LLC.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S) AND ANY CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER(S), ANY CONTRIBUTORS, THE
# UNITED STATES GOVERNMENT, OR THE UNITED STATES DEPARTMENT OF ENERGY, NOR ANY OF
# THEIR EMPLOYEES, BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# *******************************************************************************

# Dependencies
require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'openstudio-standards'
require 'fileutils'
require 'minitest/autorun'
require_relative '../measure.rb'

class HVACWidenThermostatSetpointTest < Minitest::Test
  # All tests are a sub definition of this class, e.g.:
  # def test_new_kind_of_test
  #   # test content
  # end

  def test_number_of_arguments_and_argument_names
    # This test ensures that the current test is matched to the measure inputs
    test_name = 'test_number_of_arguments_and_argument_names'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # Create an instance of the measure
    measure = HVACWidenThermostatSetpoint.new

    # Make an empty model
    model = OpenStudio::Model::Model.new

    # Get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(0, arguments.size)
  end

  # return file paths to test models in test directory
  def models_for_tests
    paths = Dir.glob(File.join(File.dirname(__FILE__), '../../../tests/models/*.osm'))
    paths = paths.map { |path| File.expand_path(path) }
    return paths
  end

  # return file paths to epw files in test directory
  def epws_for_tests
    paths = Dir.glob(File.join(File.dirname(__FILE__), '../../../tests/weather/*.epw'))
    paths = paths.map { |path| File.expand_path(path) }
    return paths
  end

  def load_model(osm_path)
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(OpenStudio::Path.new(osm_path))
    assert(!model.empty?)
    model = model.get
    return model
  end

  def run_dir(test_name)
    # Always generate test output in specially named 'output' directory so result files are not made part of the measure
    return "#{File.dirname(__FILE__)}/output/#{test_name}"
  end

  def model_output_path(test_name)
    return "#{run_dir(test_name)}/#{test_name}.osm"
  end

  def sql_path(test_name)
    return "#{run_dir(test_name)}/run/eplusout.sql"
  end

  def report_path(test_name)
    return "#{run_dir(test_name)}/reports/eplustbl.html"
  end

  # Applies the measure and then runs the model
  def apply_measure_and_run(test_name, measure, argument_map, osm_path, epw_path, run_model: false)
    assert(File.exist?(osm_path))
    assert(File.exist?(epw_path))

    # Create run directory if it does not exist
    if !File.exist?(run_dir(test_name))
      FileUtils.mkdir_p(run_dir(test_name))
    end
    assert(File.exist?(run_dir(test_name)))

    # Change into run directory for tests
    start_dir = Dir.pwd
    Dir.chdir run_dir(test_name)

    # Remove prior runs if they exist
    if File.exist?(model_output_path(test_name))
      FileUtils.rm(model_output_path(test_name))
    end
    if File.exist?(report_path(test_name))
      FileUtils.rm(report_path(test_name))
    end

    # Copy the osm and epw to the test directory
    new_osm_path = "#{run_dir(test_name)}/#{File.basename(osm_path)}"
    FileUtils.cp(osm_path, new_osm_path)
    new_epw_path = "#{run_dir(test_name)}/#{File.basename(epw_path)}"
    FileUtils.cp(epw_path, new_epw_path)
    # Create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # Load the test model
    model = load_model(new_osm_path)

    # set model weather file
    epw_file = OpenStudio::EpwFile.new(OpenStudio::Path.new(new_epw_path))
    OpenStudio::Model::WeatherFile.setWeatherFile(model, epw_file)
    assert(model.weatherFile.is_initialized)

    # Run the measure
    puts "\nAPPLYING MEASURE..."
    measure.run(model, runner, argument_map)
    result = runner.result

    # Show the output
    show_output(result)

    # Save model
    model.save(model_output_path(test_name), true)

    if run_model
      puts "\nRUNNING MODEL..."

      # Method for running the test simulation using OpenStudio 2.x API
      osw_path = File.join(run_dir(test_name), 'in.osw')
      osw_path = File.absolute_path(osw_path)

      workflow = OpenStudio::WorkflowJSON.new
      workflow.setSeedFile(File.absolute_path(model_output_path(test_name)))
      workflow.setWeatherFile(File.absolute_path(new_epw_path))
      workflow.saveAs(osw_path)

      cli_path = OpenStudio.getOpenStudioCLI
      cmd = "\"#{cli_path}\" run -w \"#{osw_path}\""
      puts cmd
      system(cmd)

      # Check that the model ran successfully
      assert(File.exist?(sql_path(test_name)))
    end

    # Change back directory
    Dir.chdir(start_dir)

    return result
  end

  # create an array of hashes with model name, weather, and expected result
  def models_to_test
    test_sets = []
    test_sets << { model: 'VAV_chiller_boiler_4A', weather: 'TN_KNOXVILLE_723260_12', result: 'Success' }
    test_sets << { model: 'PSZ-AC_with_gas_coil_heat_3B', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    test_sets << { model: 'Residential_heat_pump_3B', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    test_sets << { model: 'DOAS_wshp_gshp_3A', weather: 'GA_ROBINS_AFB_722175_12', result: 'Success' }
    return test_sets
  end

  def test_models
    test_name = 'test_models'
    puts "\n######\nTEST:#{test_name}\n######\n"

    models_to_test.each do |set|
      instance_test_name = set[:model]
      puts "instance test name: #{instance_test_name}"
      osm_path = models_for_tests.select { |x| set[:model] == File.basename(x, '.osm') }
      epw_path = epws_for_tests.select { |x| set[:weather] == File.basename(x, '.epw') }
      assert(!osm_path.empty?)
      assert(!epw_path.empty?)
      osm_path = osm_path[0]
      epw_path = epw_path[0]

      # create an instance of the measure
      measure = HVACWidenThermostatSetpoint.new

      # load the model; only used here for populating arguments
      model = load_model(osm_path)

      # set arguments here; will vary by measure
      arguments = measure.arguments(model)
      argument_map = OpenStudio::Measure::OSArgumentMap.new

      ######### Get OLD thermostat schedules for heating and cooling #########
      old_clg_profiles = []
      old_htg_profiles = []
      old_clg_values = []
      old_htg_values = []
      model.getThermalZones.each do |zone|
        next unless zone.thermostatSetpointDualSetpoint.is_initialized
        zone_thermostat = zone.thermostatSetpointDualSetpoint.get

        # Get cooling profile
        next unless zone_thermostat.coolingSetpointTemperatureSchedule.is_initialized
        clg_tstat_old = zone_thermostat.coolingSetpointTemperatureSchedule.get
        next unless clg_tstat_old.to_ScheduleRuleset.is_initialized
        clg_schedule_old = clg_tstat_old.to_ScheduleRuleset.get

        default_profile = clg_schedule_old.to_ScheduleRuleset.get.defaultDaySchedule
        old_clg_profiles << default_profile
        rules = clg_schedule_old.scheduleRules

        rules.each do |rule|
          old_clg_profiles << rule.daySchedule
        end

        # Put temperatures in values vector
        old_clg_profiles.each do |profile|
          profile.values.each do |value|
            old_clg_values << value
          end
        end

        # Re-initialize 'rules'
        rules = 0

        # Get heating profile
        next unless zone_thermostat.heatingSetpointTemperatureSchedule.is_initialized
        htg_tstat_old = zone_thermostat.heatingSetpointTemperatureSchedule.get
        next unless htg_tstat_old.to_ScheduleRuleset.is_initialized
        htg_schedule_old = htg_tstat_old.to_ScheduleRuleset.get

        default_profile = htg_schedule_old.to_ScheduleRuleset.get.defaultDaySchedule
        old_htg_profiles << default_profile
        rules = htg_schedule_old.scheduleRules

        rules.each do |rule|
          old_htg_profiles << rule.daySchedule
        end

        # Put temperatures in values vector
        old_htg_profiles.each do |profile|
          profile.values.each do |value|
            old_htg_values << value
          end
        end
      end
      ######### Get OLD thermostat schedules for heating and cooling #########

      # apply the measure to the model and optionally run the model
      result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)

      # check the measure result; result values will equal Success, Fail, or Not Applicable
      # also check the amount of warnings, info, and error messages
      # use if or case statements to change expected assertion depending on model characteristics
      assert(result.value.valueName == set[:result])

      ######### Get NEW thermostat schedules for heating and cooling to compare with old #########
      model = load_model(model_output_path(instance_test_name))
      new_clg_profiles = []
      new_htg_profiles = []
      new_clg_values = []
      new_htg_values = []
      model.getThermalZones.each do |zone|
        next unless zone.thermostatSetpointDualSetpoint.is_initialized
        zone_thermostat = zone.thermostatSetpointDualSetpoint.get

        # Get cooling profile
        next unless zone_thermostat.coolingSetpointTemperatureSchedule.is_initialized
        clg_tstat_new = zone_thermostat.coolingSetpointTemperatureSchedule.get
        next unless clg_tstat_new.to_ScheduleRuleset.is_initialized
        clg_schedule_new = clg_tstat_new.to_ScheduleRuleset.get

        default_profile = clg_schedule_new.to_ScheduleRuleset.get.defaultDaySchedule
        new_clg_profiles << default_profile
        rules = clg_schedule_new.scheduleRules

        rules.each do |rule|
          new_clg_profiles << rule.daySchedule
        end

        # Put temperatures in values vector
        new_clg_profiles.each do |profile|
          profile.values.each do |value|
            new_clg_values << value
          end
        end

        # Re-initialize 'rules'
        rules = 0

        # Get heating profile
        next unless zone_thermostat.heatingSetpointTemperatureSchedule.is_initialized
        htg_tstat_new = zone_thermostat.heatingSetpointTemperatureSchedule.get
        next unless htg_tstat_new.to_ScheduleRuleset.is_initialized
        htg_schedule_new = htg_tstat_new.to_ScheduleRuleset.get

        default_profile = htg_schedule_new.to_ScheduleRuleset.get.defaultDaySchedule
        new_htg_profiles << default_profile
        rules = htg_schedule_new.scheduleRules

        rules.each do |rule|
          new_htg_profiles << rule.daySchedule
        end

        # Put temperatures in values vector
        new_htg_profiles.each do |profile|
          profile.values.each do |value|
            new_htg_values << value
          end
        end
      end

      # Verify that the new cooling setpoints are greater than the old,
      # and that the new heating setpoints are less than the old
      assert((new_clg_values <=> old_clg_values) == 1)
      assert((new_htg_values <=> old_htg_values) == -1)
    end
  end
end