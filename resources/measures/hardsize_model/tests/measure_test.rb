# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
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

# dependencies
require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'fileutils'
require 'minitest/autorun'
require_relative '../measure.rb'

class HardsizeModelTest < Minitest::Test

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
    # always generate test output in specially named 'output' directory so result files are not made part of the measure
    return "#{File.dirname(__FILE__)}/output/#{test_name}"
  end

  def model_input_path(osm_name)
    return File.join(File.dirname(__FILE__), '../../../tests/models', osm_name)
  end

  def epw_input_path(epw_name)
    return File.join(File.dirname(__FILE__), '../../../tests/weather', epw_name)
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

  def populate_argument_map(measure, osm_path, args_hash)
    # Load the model; only used here for populating arguments
    model = load_model(osm_path)
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new

    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      if args_hash.key?(arg.name)
        assert(temp_arg_var.setValue(args_hash[arg.name]))
      end
      argument_map[arg.name] = temp_arg_var
    end

    return argument_map
  end

  # Runs the model, applies the measure, reruns the model, and checks that
  # before/after annual energy consumption results are identical
  def apply_measure_and_run(test_name, measure, argument_map, osm_path, epw_path, run_model: false, model: nil)
    assert(File.exist?(osm_path))
    assert(File.exist?(epw_path))

    # create run directory if it does not exist
    if !File.exist?(run_dir(test_name))
      FileUtils.mkdir_p(run_dir(test_name))
    end
    assert(File.exist?(run_dir(test_name)))

    # change into run directory for tests
    start_dir = Dir.pwd
    Dir.chdir run_dir(test_name)

    # remove prior runs if they exist
    if File.exist?(model_output_path(test_name))
      FileUtils.rm(model_output_path(test_name))
    end
    if File.exist?(report_path(test_name))
      FileUtils.rm(report_path(test_name))
    end

    # copy the osm and epw to the test directory
    new_osm_path = "#{run_dir(test_name)}/#{File.basename(osm_path)}"
    FileUtils.cp(osm_path, new_osm_path)
    new_epw_path = "#{run_dir(test_name)}/#{File.basename(epw_path)}"
    FileUtils.cp(epw_path, new_epw_path)
    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # load the test model
    if model.nil?
      model = load_model(new_osm_path)
    end

    # set model weather file
    epw_file = OpenStudio::EpwFile.new(OpenStudio::Path.new(new_epw_path))
    OpenStudio::Model::WeatherFile.setWeatherFile(model, epw_file)
    assert(model.weatherFile.is_initialized)

    # Change the runperiod to 1 week for testing only
    run_period = model.getRunPeriod
    run_period.setBeginMonth(4)
    run_period.setBeginDayOfMonth(1)
    run_period.setEndMonth(4)
    run_period.setEndDayOfMonth(15)
    run_period.setNumTimePeriodRepeats(1)

    # Run the model before applying the measure and get annual energy consumption
    std = Standard.build('90.1-2013')
    if run_model
      puts "\nRUNNING MODEL BEFORE MEASURE..."
      assert(std.model_run_simulation_and_log_errors(model, File.join(run_dir(test_name), 'run_autosized_before')))
    end
    tot_engy_bef = model.sqlFile.get.totalSiteEnergy.get

    # Run the measure
    puts "\nAPPLYING MEASURE..."
    measure.run(model, runner, argument_map)
    result = runner.result
    result_success = result.value.valueName == 'Success'

    # Show the output
    show_output(result)

    # Save model
    model.save(model_output_path(test_name), true)

    # Run the model after applying the measure and get annual energy consumption
    if run_model && result_success
      puts "\nRUNNING MODEL AFTER MEASURE..."
      assert(std.model_run_simulation_and_log_errors(model, File.join(run_dir(test_name), 'run_hardsized_after')))
      tot_engy_aft = model.sqlFile.get.totalSiteEnergy.get
    end

    # Assert that there was no change in energy consumption caused by
    # hard-sizing the model.
    assert_equal(tot_engy_bef, tot_engy_aft)

    # change back directory
    Dir.chdir(start_dir)

    return result
  end

  def dont_test_number_of_arguments_and_argument_names
    # Create an instance of the measure
    measure = HardsizeModel.new

    # Make an empty model
    model = OpenStudio::Model::Model.new

    # Get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(1, arguments.size)
  end

  def test_outpatient_vav_chiller_pfp_boxes
    osm_name = 'Outpatient_VAV_chiller_PFP_boxes.osm'
    epw_name = 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16.epw'
    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)
    measure = HardsizeModel.new
    args_hash = {'apply_hardsize' => true}
    argument_map = populate_argument_map(measure, osm_path, args_hash)
    # Apply the measure and check if before/after results are identical
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: true)
  end

  def test_largeoffice_vav_district_chw_hw
    osm_name = 'LargeOffice_VAV_district_chw_hw.osm'
    epw_name = 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16.epw'
    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)
    measure = HardsizeModel.new
    args_hash = {'apply_hardsize' => true}
    argument_map = populate_argument_map(measure, osm_path, args_hash)
    # Apply the measure and check if before/after results are identical
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: true)
  end

  def test_largeoffice_vav_chiller_boiler
    osm_name = 'LargeOffice_VAV_chiller_boiler.osm'
    epw_name = 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16.epw'
    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)
    measure = HardsizeModel.new
    args_hash = {'apply_hardsize' => true}
    argument_map = populate_argument_map(measure, osm_path, args_hash)
    # Apply the measure and check if before/after results are identical
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: true)
  end

  def test_largeoffice_vav_chiller_boiler_2
    osm_name = 'LargeOffice_VAV_chiller_boiler_2.osm'
    epw_name = 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16.epw'
    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)
    measure = HardsizeModel.new
    args_hash = {'apply_hardsize' => true}
    argument_map = populate_argument_map(measure, osm_path, args_hash)
    # Apply the measure and check if before/after results are identical
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: true)
  end

  def test_retail_pvav_gas_ht_elec_rht
    osm_name = 'Retail_PVAV_gas_ht_elec_rht.osm'
    epw_name = 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16.epw'
    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)
    measure = HardsizeModel.new
    args_hash = {'apply_hardsize' => true}
    argument_map = populate_argument_map(measure, osm_path, args_hash)
    # Apply the measure and check if before/after results are identical
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: true)
  end

  def test_secondaryschool_pthp
    osm_name = 'SecondarySchool_PTHP.osm'
    epw_name = 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16.epw'
    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)
    measure = HardsizeModel.new
    args_hash = {'apply_hardsize' => true}
    argument_map = populate_argument_map(measure, osm_path, args_hash)
    # Apply the measure and check if before/after results are identical
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: true)
  end

  def test_retail_psz_ac
    osm_name = 'Retail_PSZ-AC.osm'
    epw_name = 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16.epw'
    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)
    measure = HardsizeModel.new
    args_hash = {'apply_hardsize' => true}
    argument_map = populate_argument_map(measure, osm_path, args_hash)
    # Apply the measure and check if before/after results are identical
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: true)
  end
end
