# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.


# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/
require 'openstudio-standards'

# start the measure
class AddHeatPumpRtu < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'add_heat_pump_rtu'
  end

  # human readable description
  def description
    return 'Measure replaces existing packaged single-zone RTU system types with heat pump RTUs. Not applicable for water coil systems.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Modeler has option to set backup heat source, prevelence of heat pump oversizing, heat pump oversizing limit, and addition of energy recovery. This measure will work on unitary PSZ systems as well as single-zone, constant air volume air loop PSZ systems.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # make list of backup heat options
    li_backup_heat_options = ["match_original_primary_heating_fuel", "electric_resistance_backup"]
    v_backup_heat_options = OpenStudio::StringVector.new
    li_backup_heat_options.each do |option|
      v_backup_heat_options << option
    end
    # add backup heat option arguments
    backup_ht_fuel_scheme = OpenStudio::Measure::OSArgument.makeChoiceArgument('backup_ht_fuel_scheme', v_backup_heat_options, true)
    backup_ht_fuel_scheme.setDisplayName('Backup Heat Type')
    backup_ht_fuel_scheme.setDescription('Specifies if the backup heat fuel type is a gas furnace or electric resistance coil. If match original primary heating fuel is selected, the heating fuel type will match the primary heating fuel type of the original model. If electric resistance is selected, AHUs will get electric resistance backup.')
    backup_ht_fuel_scheme.setDefaultValue("electric_resistance_backup")
    args << backup_ht_fuel_scheme

    # add RTU oversizing factor for heating
    performance_oversizing_factor = OpenStudio::Measure::OSArgument.makeDoubleArgument('performance_oversizing_factor', true)
    performance_oversizing_factor.setDisplayName('Maximum Performance Oversizing Factor')
    performance_oversizing_factor.setDefaultValue(0)
    performance_oversizing_factor.setDescription('When heating design load exceeds cooling design load, the design cooling capacity of the unit will only be allowed to increase up to this factor to accomodate additional heating capacity. Oversizing the compressor beyond 25% can cause cooling cycling issues, even with variable speed compressors.')
    args << performance_oversizing_factor

    # heating sizing options TODO
    li_htg_sizing_option = ['47F', '17F', '0F']
    v_htg_sizing_option = OpenStudio::StringVector.new
    li_htg_sizing_option.each do |option|
      v_htg_sizing_option << option
    end

    htg_sizing_option = OpenStudio::Measure::OSArgument.makeChoiceArgument('htg_sizing_option', li_htg_sizing_option, true)
    htg_sizing_option.setDefaultValue('0F')
    htg_sizing_option.setDisplayName('Temperature to Sizing Heat Pump, F')
    htg_sizing_option.setDescription('Specifies temperature to size heating on. If design temperature for climate is higher than specified, program will use design temperature. Heat pump sizing will not exceed user-input oversizing factor.')
    args << htg_sizing_option

    # add assumed oversizing factor for cooling
    clg_oversizing_estimate = OpenStudio::Measure::OSArgument.makeDoubleArgument('clg_oversizing_estimate', true)
    clg_oversizing_estimate.setDisplayName('Cooling Upsizing Factor Estimate')
    clg_oversizing_estimate.setDefaultValue(1)
    clg_oversizing_estimate.setDescription('RTU selection involves sizing up to unit that meets your capacity needs, which creates natural oversizing. This factor estimates this oversizing. E.G. the sizing calc may require 8.7 tons of cooling, but the size options are 7.5 tons and 10 tons, so you choose the 10 ton unit. A value of 1 means to upsizing.')
    args << clg_oversizing_estimate

    # add ratio of heating to cooling
    htg_to_clg_hp_ratio = OpenStudio::Measure::OSArgument.makeDoubleArgument('htg_to_clg_hp_ratio', true)
    htg_to_clg_hp_ratio.setDisplayName('Rated HP Heating to Cooling Ratio')
    htg_to_clg_hp_ratio.setDefaultValue(1)
    htg_to_clg_hp_ratio.setDescription('At rated conditions, a compressor will generally have slightly more cooling capacity than heating capacity. This factor integrates this ratio into the unit sizing.')
    args << htg_to_clg_hp_ratio

    # add heat recovery option
    hr = OpenStudio::Measure::OSArgument.makeBoolArgument('hr', true)
    hr.setDisplayName('Add Energy Recovery?')
    hr.setDefaultValue(false)
    args << hr

    # add dcv option
    dcv = OpenStudio::Measure::OSArgument.makeBoolArgument('dcv', true)
    dcv.setDisplayName('Add Demand Control Ventilation?')
    dcv.setDefaultValue(false)
    args << dcv

    # add economizer option
    econ = OpenStudio::Measure::OSArgument.makeBoolArgument('econ', true)
    econ.setDisplayName('Add Economizer?')
    econ.setDefaultValue(false)
    args << econ

    return args
  end

  # define the outputs that the measure will create
  def outputs

    # outs = OpenStudio::Measure::OSOutputVector.new
    output_names = []

    result = OpenStudio::Measure::OSOutputVector.new
    output_names.each do |output|
      result << OpenStudio::Measure::OSOutput.makeDoubleOutput(output)
    end

    return result
  end

  #### Predefined functions
  # determine if the air loop is residential (checks to see if there is outdoor air system object)
  def air_loop_res?(air_loop_hvac)
    is_res_system = true
    air_loop_hvac.supplyComponents.each do |component|
      obj_type = component.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_AirLoopHVAC_OutdoorAirSystem'
        is_res_system = false
      end
    end
    return is_res_system
  end

  # Determine if is evaporative cooler
  def air_loop_evaporative_cooler?(air_loop_hvac)
    is_evap = false
    air_loop_hvac.supplyComponents.each do |component|
      obj_type = component.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_EvaporativeCooler_Direct_ResearchSpecial', 'OS_EvaporativeCooler_Indirect_ResearchSpecial', 'OS_EvaporativeFluidCooler_SingleSpeed', 'OS_EvaporativeFluidCooler_TwoSpeed'
        is_evap = true
      end
    end
    return is_evap
  end

  # Determine if the air loop is a unitary system
  # @return [Bool] Returns true if a unitary system is present, false if not.
  def air_loop_hvac_unitary_system?(air_loop_hvac)
    is_unitary_system = false
    air_loop_hvac.supplyComponents.each do |component|
      obj_type = component.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_AirLoopHVAC_UnitarySystem', 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir', 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir_MultiSpeed', 'OS_AirLoopHVAC_UnitaryHeatCool_VAVChangeoverBypass'
        is_unitary_system = true
      end
    end
    return is_unitary_system
  end
  #### End predefined functions

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # assign the user inputs to variables
    backup_ht_fuel_scheme = runner.getStringArgumentValue('backup_ht_fuel_scheme', user_arguments)
    # prim_ht_fuel_type = runner.getStringArgumentValue('prim_ht_fuel_type', user_arguments)
    performance_oversizing_factor = runner.getDoubleArgumentValue('performance_oversizing_factor', user_arguments)
    htg_sizing_option = runner.getStringArgumentValue('htg_sizing_option', user_arguments)
    clg_oversizing_estimate = runner.getDoubleArgumentValue('clg_oversizing_estimate', user_arguments)
    htg_to_clg_hp_ratio = runner.getDoubleArgumentValue('htg_to_clg_hp_ratio', user_arguments)
    hr = runner.getBoolArgumentValue('hr', user_arguments)
    dcv = runner.getBoolArgumentValue('dcv', user_arguments)
    econ = runner.getBoolArgumentValue('econ', user_arguments)

    # build standard to use OS standards methods
    template = 'ComStock 90.1-2019'
    std = Standard.build(template)
    # get climate zone value
    climate_zone = std.model_standards_climate_zone(model)

    # get applicable psz hvac air loops
    selected_air_loops = []
    applicable_area_m2 = 0
    prim_ht_fuel_type = 'electric' # we assume electric unless we find a gas coil in any air loop
    model.getAirLoopHVACs.each do |air_loop_hvac|
      # skip units that are not single zone
      next if air_loop_hvac.thermalZones.length() > 1
      # skip DOAS units; check sizing for all OA and for DOAS in name
      sizing_system = air_loop_hvac.sizingSystem
      next if sizing_system.allOutdoorAirinCooling && sizing_system.allOutdoorAirinHeating && (air_loop_res?(air_loop_hvac) == false) && (air_loop_hvac.name.to_s.include?("DOAS") || air_loop_hvac.name.to_s.include?("doas"))
      # skip if already heat pump RTU
      # loop throug air loop components to check for heat pump or water coils
      is_hp=false
      is_water_coil=false
      has_heating_coil=true
      air_loop_hvac.supplyComponents.each do |component|
        obj_type = component.iddObjectType.valueName.to_s
        # flag system if contains water coil; this will cause air loop to be skipped
        is_water_coil=true if ['Coil_Heating_Water', 'Coil_Cooling_Water'].any? { |word| (obj_type).include?(word) }
        # flag gas heating as true if gas coil is found in any airloop
        prim_ht_fuel_type= 'gas' if ['Gas', 'GAS', 'gas'].any? { |word| (obj_type).include?(word) }
        # check unitary systems for DX heating or water coils
        if  obj_type=='OS_AirLoopHVAC_UnitarySystem'
          unitary_sys = component.to_AirLoopHVACUnitarySystem.get

          # check if heating coil is DX or water-based; if so, flag the air loop to be skipped
          if unitary_sys.heatingCoil.is_initialized
            htg_coil = unitary_sys.heatingCoil.get.iddObjectType.valueName.to_s
            # check for DX heating coil
            if ['Heating_DX'].any? { |word| (htg_coil).include?(word) }
              is_hp=true
            # check for water heating coil
            elsif ['Water'].any? { |word| (htg_coil).include?(word) }
              is_water_coil=true
            # check for gas heating
            elsif ['Gas', 'GAS', 'gas'].any? { |word| (htg_coil).include?(word) }
              prim_ht_fuel_type='gas'
            end
          else
            runner.registerWarning("No heating coil was found for air loop: #{air_loop_hvac.name} - this equipment will be skipped.")
            has_heating_coil = false
          end
          # check if cooling coil is water-based
          if unitary_sys.coolingCoil.is_initialized
            clg_coil = unitary_sys.coolingCoil.get.iddObjectType.valueName.to_s
            # skip unless coil is water based
            next unless ['Water'].any? { |word| (clg_coil).include?(word) }
            is_water_coil=true
          end
        # flag as hp if air loop contains a heating dx coil
        elsif ['Heating_DX'].any? { |word| (obj_type).include?(word) }
          is_hp=true
        end
      end
      # also skip based on string match, or if dx heating component existed
      next if (is_hp==true) | (((air_loop_hvac.name.to_s.include?("HP")) || (air_loop_hvac.name.to_s.include?("hp")) || (air_loop_hvac.name.to_s.include?("heat pump")) || (air_loop_hvac.name.to_s.include?("Heat Pump"))))
      # skip data centers
      next if ['Data Center', 'DataCenter', 'data center', 'datacenter', 'DATACENTER', 'DATA CENTER'].any? { |word| (air_loop_hvac.name.get).include?(word) }
      # skip kitchens
      next if ['Kitchen', 'KITCHEN', 'Kitchen'].any? { |word| (air_loop_hvac.name.get).include?(word) }
      # skip VAV sysems
      next if ['VAV', 'PVAV'].any? { |word| (air_loop_hvac.name.get).include?(word) }
      # skip if residential system
      next if air_loop_res?(air_loop_hvac)
      # skip if system has no outdoor air, also indication of residential system
      next unless air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
      # skip if evaporative cooling systems
      next if air_loop_evaporative_cooler?(air_loop_hvac)
      # skip if water heating or cooled system
      next if is_water_coil==true
      # skip if space is not heated and cooled
      next unless (std.thermal_zone_heated?(air_loop_hvac.thermalZones[0])) && (std.thermal_zone_cooled?(air_loop_hvac.thermalZones[0]))
      # next if no heating coil
      next if has_heating_coil == false
      # add applicable air loop to list
      selected_air_loops << air_loop_hvac
      # add area served by air loop
      thermal_zone = air_loop_hvac.thermalZones[0]
      applicable_area_m2+=thermal_zone.floorArea
    end

    # check if any air loops are applicable to measure
    if selected_air_loops.empty?
      runner.registerAsNotApplicable('No applicable air loops in model. No changes will be made.')
      return true
    end

    # do sizing run with new equipment to set sizing-specific features
    if std.model_run_sizing_run(model, "#{Dir.pwd}/SR_HP") == false
    return false
    end

    #########################################################################################################
    ### This section includes temporary code to remove units with high OA fractiosn and night cycling
    ### This code should be removed when fix is initiated
    # add systems with high outdoor air ratios to a list for non-applicability
    oa_ration_allowance = 0.55
    selected_air_loops.each do |air_loop_hvac|

      puts air_loop_hvac.name

      thermal_zone = air_loop_hvac.thermalZones[0]

      # get the min OA flow rate for calculating unit OA fraction
      oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
      controller_oa = oa_system.getControllerOutdoorAir
      oa_flow_m3_per_s = nil
      if controller_oa.minimumOutdoorAirFlowRate.is_initialized
        oa_flow_m3_per_s = controller_oa.minimumOutdoorAirFlowRate.get
      elsif controller_oa.autosizedMinimumOutdoorAirFlowRate.is_initialized 
        oa_flow_m3_per_s = controller_oa.autosizedMinimumOutdoorAirFlowRate.get
      else
        runner.registerError("No outdoor air sizing information was found for #{controller_oa.name}, which is required for setting ERV wheel power consumption.")
        return false
      end

      # get design supply air flow rate
      # get old terminal box
      if thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctConstantVolumeNoReheat.is_initialized
        old_terminal = thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctConstantVolumeNoReheat.get
      else
        runner.registerError("Terminal box type for air loop #{air_loop_hvac.name} not supported.")
        return false
      end
      # get sizing information from terminal box
      if old_terminal.isMaximumAirFlowRateAutosized == true
        old_terminal_sa_flow_m3_per_s = old_terminal.autosizedMaximumAirFlowRate.get
      elsif old_terminal.maximumAirFlowRate.is_initialized
        old_terminal_sa_flow_m3_per_s = old_terminal.maximumAirFlowRate.get
      else
        runner.registerError("No sizing data available for air loop #{air_loop_hvac.name} zone terminal box.")
      end
      # define minimum flow rate needed to maintain ventilation - add in max fraction if in model
      min_oa_flow_ratio = (oa_flow_m3_per_s/old_terminal_sa_flow_m3_per_s)

      # register as not applicable if oa limit is reached
      exceeds_oa_limit = true unless (oa_ration_allowance > min_oa_flow_ratio)
      
      
      # check to see if there is night cycling operation for unit
      night_cyc_sched_vals = []
      air_loop_hvac.supplyComponents.each do |component|

        # convert component to string name
        obj_type = component.iddObjectType.valueName.to_s
        # skip unless component is of relevant type
        next unless ['Unitary'].any? { |word| (obj_type).include?(word) }
        unitary_sys = component.to_AirLoopHVACUnitarySystem.get 
        # get supply fan operating schedule
        next unless unitary_sys.supplyAirFanOperatingModeSchedule.is_initialized
        sf_sched = unitary_sys.supplyAirFanOperatingModeSchedule.get
        if sf_sched.to_ScheduleRuleset.is_initialized
          sf_sched = sf_sched.to_ScheduleRuleset.get
        elsif sf_sched.to_ScheduleConstant.is_initialized
          sf_sched = sf_sched.to_ScheduleConstant.get
        end

        if sf_sched.to_ScheduleRuleset.is_initialized
          sf_sched_rules_ar = sf_sched.scheduleRules
          # loop through schedules in ruleset
          sf_sched_rules_ar.each do |sched_rule|
            sched_values = sched_rule.daySchedule.values
            # loop through schedule values and add to array
            sched_values.each do |value|
              night_cyc_sched_vals << value
            end
          end
        elsif sf_sched.to_ScheduleConstant.is_initialized
          value = sf_sched.value
          night_cyc_sched_vals << value
        end
      end

      # if supply operating schedule does not include a 0, the unit does not night cycle
      unit_night_cycles=true
      if (night_cyc_sched_vals.include? [0, 0.0]) 
        unit_night_cycles=true
      else
        unit_night_cycles=false
      end

      # register as not applicable if OA limit exceeded and unit has night cycling schedules
      if (min_oa_flow_ratio > oa_ration_allowance) && (unit_night_cycles==true)
        runner.registerWarning("Air loop #{air_loop_hvac.name} has night cycling operations and an outdoor air ratio of #{min_oa_flow_ratio.round(2)} which exceeds the maximum allowable limit of #{oa_ration_allowance} (due to an EnergyPlus night cycling bug with multispeed coils) making this RTU not applicable at this time.")
        # remove air loop from applicable list
        selected_air_loops.delete(air_loop_hvac)
        applicable_area_m2 -= thermal_zone.floorArea
        # remove area served by air loop from applicability
      end
    end
    ### End of temp section
    #########################################################################################################

    # model.autosize()

    runner.registerInfo("#{selected_air_loops.size}")

    # check if any air loops are applicable to measure
    if selected_air_loops.empty?
      runner.registerAsNotApplicable('No applicable air loops in model. No changes will be made.')
      return true
    end


    # get model conditioned square footage for reporting
    if model.building.get.conditionedFloorArea.empty?
      runner.registerError("model.building.get.conditionedFloorArea() is empty.")
      return true
    else
      total_area_m2 = model.building.get.conditionedFloorArea.get
    end

    # fraction of conditioned floorspace
    applicable_floorspace_frac = applicable_area_m2 / total_area_m2

    # report initial condition of model
    runner.registerInitialCondition("The building has #{selected_air_loops.size} applicable air loops that will be replaced with heat pump RTUs, representing #{(applicable_floorspace_frac*100).round(2)}% of the building floor area.")

    backup_heat_source=nil
    # report gas heating as backup source
    if (prim_ht_fuel_type == 'gas') && (backup_ht_fuel_scheme=='match_original_primary_heating_fuel')
      runner.registerInfo("Gas heating was found in an airloop, and the user chose to add backup heat that matches the original fuel source of the building. Therefore, any heat pump backup heat added to model will be gas.")
      backup_heat_source='gas'
    elsif (prim_ht_fuel_type == 'electric') && (backup_ht_fuel_scheme=='match_original_primary_heating_fuel')
      runner.registerInfo("No gas heating coil was found, so electric heating is assumed in original model. The user chose to add backup heat with a fuel type that matches the original model, therefore any heat pump backup heat added will be electric.")
      backup_heat_source='electric'
    elsif (backup_ht_fuel_scheme=='electric_resistance_backup')
      runner.registerInfo("The user specified the use of electric resistance backup heat for heat pumps, so all backup heat will be electric.")
      backup_heat_source='electric'
    else
      runner.registerInfo("Based on model features and user-inputs, heat pump backup heat will be electric resistance.")
      backup_heat_source='electric'
    end

    # make list of dummy heating coils; these are used to determine actual heating load, but need to be deleted later
    li_dummy_htg_coils = []
    # replace existing applicable air loops with new heat pump rtu air loops
    selected_air_loops.sort.each do |air_loop_hvac|

      # get necessary schedules, etc. from unitary system object
      # initialize variables before loop
      hvac_operation_sched=air_loop_hvac.availabilitySchedule
      unitary_availability_sched='tmp'
      control_zone='tmp'
      dehumid_type='tmp'
      supply_fan_op_sched='tmp'
      supply_fan_avail_sched='tmp'
      fan_tot_eff='tmp'
      fan_mot_eff='tmp'
      fan_static_pressure='tmp'
      supply_air_flow_m3_per_s='tmp'
      orig_clg_coil_gross_cap=nil
      orig_htg_coil_gross_cap=nil

      equip_to_delete=[]

      # for unitary systems
      if air_loop_hvac_unitary_system?(air_loop_hvac)

        # loop through each relevant component.
        # store information needed as variable
        # remove the existing equipment
        air_loop_hvac.supplyComponents.each do |component|

          # convert component to string name
          obj_type = component.iddObjectType.valueName.to_s
          # skip unless component is of relevant type
          next unless ['Fan', 'Unitary', 'Coil'].any? { |word| (obj_type).include?(word) }

          # make list of equipment to delete
          equip_to_delete << component

          # get information specifically from unitary system object
          if ['Unitary'].any? { |word| (obj_type).include?(word)} # TODO: There are more unitary systems types we are not including here
            # get unitary system
            unitary_sys = component.to_AirLoopHVACUnitarySystem.get 
            # get availability schedule
            unitary_availability_sched = unitary_sys.availabilitySchedule.get 
            # get control zone
            control_zone = unitary_sys.controllingZoneorThermostatLocation.get
            # get dehumidification control type
            dehumid_type = unitary_sys.dehumidificationControlType
            # get supply fan operation schedule
            supply_fan_op_sched = unitary_sys.supplyAirFanOperatingModeSchedule.get
            # get supply fan availability schedule
            supply_fan = unitary_sys.supplyFan.get
            # convert supply fan to appropriate object to access methods
            if supply_fan.to_FanConstantVolume.is_initialized
              supply_fan = supply_fan.to_FanConstantVolume.get
            elsif supply_fan.to_FanOnOff.is_initialized
              supply_fan = supply_fan.to_FanOnOff.get
            elsif supply_fan.to_FanVariableVolume.is_initialized
              supply_fan = supply_fan.to_FanVariableVolume.get
            else
              runner.registerError("Supply fan type for #{air_loop_hvac.name} not supported.")
              return false
            end
            # get the availability schedule
            supply_fan_avail_sched = supply_fan.availabilitySchedule
            if supply_fan_avail_sched.to_ScheduleConstant.is_initialized
              supply_fan_avail_sched=supply_fan_avail_sched.to_ScheduleConstant.get
            elsif supply_fan_avail_sched.to_ScheduleRuleset.is_initialized
              supply_fan_avail_sched=supply_fan_avail_sched.to_ScheduleConstant.get
            else
              runner.registerError("Supply fan availability schedule type for #{supply_fan.name} not supported.")
              return false
            end
            # get supply fan motor efficiency
            fan_tot_eff = supply_fan.fanTotalEfficiency
            # get supply motor efficiency
            fan_mot_eff = supply_fan.motorEfficiency
            # get supply fan static pressure
            fan_static_pressure = supply_fan.pressureRise
            # get previous cooling coil capacity
            orig_clg_coil = unitary_sys.coolingCoil.get
            if orig_clg_coil.to_CoilCoolingDXSingleSpeed.is_initialized
              orig_clg_coil = orig_clg_coil.to_CoilCoolingDXSingleSpeed.get
              # get either autosized or specified cooling capacity
              if orig_clg_coil.isRatedTotalCoolingCapacityAutosized == true
                orig_clg_coil_gross_cap = orig_clg_coil.autosizedRatedTotalCoolingCapacity.get
              elsif orig_clg_coil.ratedTotalCoolingCapacity.is_initialized
                orig_clg_coil_gross_cap = orig_clg_coil.ratedTotalCoolingCapacity.to_f
              else
                runner.registerError("Original cooling coil capacity for #{air_loop_hvac.name} not found. Either it was not directly specified, or sizing run data is not available.")
              end
            end
            # get original heating coil capacity
            orig_htg_coil = unitary_sys.heatingCoil.get
            # get coil object if electric resistance
            if orig_htg_coil.to_CoilHeatingElectric.is_initialized 
              orig_htg_coil = orig_htg_coil.to_CoilHeatingElectric.get
            # get coil object if gas
            elsif orig_htg_coil.to_CoilHeatingGas.is_initialized
              orig_htg_coil = orig_htg_coil.to_CoilHeatingGas.get
            else
              runner.registerError("Heating coil for #{air_loop_hvac.name} is of an unsupported type. This measure currently supports CoilHeatingElectric and CoilHeatingGas object types.")
            end
            # get either autosized or specified capacity
            if orig_htg_coil.isNominalCapacityAutosized == true
              orig_htg_coil_gross_cap = orig_htg_coil.autosizedNominalCapacity.get
            elsif orig_htg_coil.nominalCapacity.is_initialized
              orig_htg_coil_gross_cap = orig_htg_coil.nominalCapacity.to_f
            else
              runner.registerError("Original heating coil capacity for #{air_loop_hvac.name} not found. Either it was not directly specified, or sizing run data is not available.")
            end
          end
        end

      # get non-unitary system objects.
      else
        # loop through components
        air_loop_hvac.supplyComponents.each do |component|
          # convert component to string name
          obj_type = component.iddObjectType.valueName.to_s
          # skip unless component is of relevant type
          next unless ['Fan', 'Unitary', 'Coil'].any? { |word| (obj_type).include?(word) }
          # make list of equipment to delete
          equip_to_delete << component
          # check for fan
          if ['Fan'].any? { |word| (obj_type).include?(word)}
            supply_fan = component
            if supply_fan.to_FanConstantVolume.is_initialized
              supply_fan = supply_fan.to_FanConstantVolume.get
            elsif supply_fan.to_FanOnOff.is_initialized
              supply_fan = supply_fan.to_FanOnOff.get
            elsif supply_fan.to_FanVariableVolume.is_initialized
              supply_fan = supply_fan.to_FanVariableVolume.get
            else
              runner.registerError("Supply fan type for #{air_loop_hvac.name} not supported.")
              return false
            end
            # get the availability schedule
            supply_fan_avail_sched = supply_fan.availabilitySchedule
            if supply_fan_avail_sched.to_ScheduleConstant.is_initialized
              supply_fan_avail_sched=supply_fan_avail_sched.to_ScheduleConstant.get
            elsif supply_fan_avail_sched.to_ScheduleRuleset.is_initialized
              supply_fan_avail_sched=supply_fan_avail_sched.to_ScheduleConstant.get
            else
              runner.registerError("Supply fan availability schedule type for #{supply_fan.name} not supported.")
              return false
            end
            # get supply fan motor efficiency
            fan_tot_eff = supply_fan.fanTotalEfficiency
            # get supply motor efficiency
            fan_mot_eff = supply_fan.motorEfficiency
            # get supply fan static pressure
            fan_static_pressure = supply_fan.pressureRise
            # set unitary supply fan operating schedule equal to system schedule for non-unitary systems
            supply_fan_op_sched = hvac_operation_sched
            # set dehumidification type
            dehumid_type = 'None'
            # set control zone to the thermal zone. This will be used in new unitary system object
            control_zone = air_loop_hvac.thermalZones[0]
            # set unitary availability schedule to be always on. This will be used in new unitary system object.
            unitary_availability_sched =  model.alwaysOnDiscreteSchedule
          end
        end
      end

      # delete equipment from original loop
      equip_to_delete.each(&:remove)

      # set always on schedule; this will be used in other object definitions
      always_on = model.alwaysOnDiscreteSchedule

      # get thermal zone
      thermal_zone = air_loop_hvac.thermalZones[0]

      # Get the min OA flow rate from the OA; this is used below
      oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
      controller_oa = oa_system.getControllerOutdoorAir
      oa_flow_m3_per_s = nil
      if controller_oa.minimumOutdoorAirFlowRate.is_initialized
        oa_flow_m3_per_s = controller_oa.minimumOutdoorAirFlowRate.get
      elsif controller_oa.autosizedMinimumOutdoorAirFlowRate.is_initialized
        oa_flow_m3_per_s = controller_oa.autosizedMinimumOutdoorAirFlowRate.get
      else
        runner.registerError("No outdoor air sizing information was found for #{controller_oa.name}, which is required for setting ERV wheel power consumption.")
        return false
      end

      # change sizing parameter to vav
      sizing = air_loop_hvac.sizingSystem
      sizing.setCentralCoolingCapacityControlMethod('VAV') #CC-TMP
      # # change discharge air temperature to 105F to represent lower heat pump temps
      # hp_htg_sa_temp_c = OpenStudio.convert(105.00000000000000, 'F', 'C').get #CC-TMP
      # sizing.setCentralHeatingDesignSupplyAirTemperature(hp_htg_sa_temp_c)
      # # change discharge air temperature in thermal zone
      # zone_sizing = thermal_zone.sizingZone
      # zone_sizing.setZoneHeatingDesignSupplyAirTemperature(hp_htg_sa_temp_c)
      # # check if setpoint manager is present at supply outlet
      # # this will work for single zone reheat setpoint managers only
      # model.getSetpointManagerSingleZoneReheats.sort.each do |sp_manager|
      #   if air_loop_hvac.supplyOutletNode == sp_manager.setpointNode.get
      #     # for current setpoint managet, change supply outlet temp to 105F
      #     sp_manager.setMaximumSupplyAirTemperature(hp_htg_sa_temp_c)
      #   end
      # end

      # replace any CV terminal box with no reheat VAV terminal box
      # get old terminal box
      if  thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctConstantVolumeReheat.is_initialized
        old_terminal = thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctConstantVolumeReheat.get
      elsif thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctConstantVolumeNoReheat.is_initialized
        old_terminal = thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctConstantVolumeNoReheat.get
      elsif thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctVAVHeatAndCoolNoReheat.is_initialized
        old_terminal = thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctVAVHeatAndCoolNoReheat.get
      elsif thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctVAVHeatAndCoolReheat.is_initialized
        old_terminal = thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctVAVHeatAndCoolReheat.get
      elsif thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctVAVNoReheat.is_initialized
        old_terminal = thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctVAVNoReheat.get
      elsif thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctVAVReheat.is_initialized
        old_terminal = thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctVAVReheat.get
      else
        runner.registerError("Terminal box type for air loop #{air_loop_hvac.name} not supported.")
        return false
      end

      # get sizing information from terminal box
      if old_terminal.isMaximumAirFlowRateAutosized == true
        old_terminal_sa_flow_m3_per_s = old_terminal.autosizedMaximumAirFlowRate.get
      elsif old_terminal.maximumAirFlowRate.is_initialized
        old_terminal_sa_flow_m3_per_s = old_terminal.maximumAirFlowRate.get
      else
        runner.registerError("No sizing data available for air loop #{air_loop_hvac.name} zone terminal box.")
      end

      # define minimum flow rate needed to maintain ventilation - add in max fraction if in model
      if controller_oa.maximumFractionofOutdoorAirSchedule.is_initialized
        controller_oa.resetMaximumFractionofOutdoorAirSchedule
        # min_flow_ratio = ((oa_flow_m3_per_s/0.75)/old_terminal_sa_flow_m3_per_s).round(2)
        min_oa_flow_ratio = (oa_flow_m3_per_s/old_terminal_sa_flow_m3_per_s)
      else
        min_oa_flow_ratio = (oa_flow_m3_per_s/old_terminal_sa_flow_m3_per_s)
      end

      # # register as not applicable if OA limit exceeded and unit has night cycling schedules
      # if (oa_flow_m3_per_s/old_terminal_sa_flow_m3_per_s) > 0.6
      #   runner.registerAsNotApplicable("Air loop #{air_loop_hvac.name} has an outdoor air ratio of #{(oa_flow_m3_per_s/old_terminal_sa_flow_m3_per_s).round(2)} which exceeds the maximum allowable limit of 0.60 (due to an EnergyPlus night cycling bug with multispeed coils) making this model not applicable at this time.")
      #   return false
      # end

      # remove old equipment
      old_terminal.remove
      air_loop_hvac.removeBranchForZone(thermal_zone)
      # define new terminal box
      new_terminal = OpenStudio::Model::AirTerminalSingleDuctConstantVolumeNoReheat.new(model,always_on)

      # # set minimum flow rate to 0.40, or higher as needed to maintain outdoor air requirements
      min_flow = 0.40 

      # set name of terminal box and add
      new_terminal.setName("#{thermal_zone.name} VAV Terminal")
      air_loop_hvac.addBranchForZone(thermal_zone, new_terminal.to_StraightComponent)

      # determine minimum airflow ratio for sizing; 0.4 is used unless OA requires higher
      if min_oa_flow_ratio > min_flow
        min_airflow_ratio = min_oa_flow_ratio
        min_airflow_m3_per_s = min_oa_flow_ratio * old_terminal_sa_flow_m3_per_s
      else
        min_airflow_ratio = min_flow
        min_airflow_m3_per_s = min_airflow_ratio * old_terminal_sa_flow_m3_per_s
      end

      #################################### Start Sizing Logic

      # get heating design day temperatures into list
      li_design_days = model.getDesignDays
      li_htg_dsgn_day_temps = []
      # loop through list of design days, add heating temps
      li_design_days.sort.each do |dd|
        day_type = dd.dayType
        # add design day drybulb temperature if winter design day
        next unless day_type == 'WinterDesignDay'
        li_htg_dsgn_day_temps << dd.maximumDryBulbTemperature
      end
      # get coldest design day temp for manual sizing
      wntr_design_day_temp_c = li_htg_dsgn_day_temps.min()

      # get user-input heating sizing temperature
      htg_sizing_option_hash = {'47F'=>47, '17F'=>17, '0F'=>0}
      htg_sizing_option_f = htg_sizing_option_hash[htg_sizing_option]
      htg_sizing_option_c = OpenStudio.convert(htg_sizing_option_f, 'F', 'C').get
      hp_sizing_temp_c = nil
      # set heat pump sizing temp based on user-input value and design day
      if htg_sizing_option_c >= wntr_design_day_temp_c
        hp_sizing_temp_c = htg_sizing_option_c
        runner.registerInfo("For heat pump sizing, heating design day temperature is #{OpenStudio.convert(wntr_design_day_temp_c, 'C', 'F').get.round(0)}F, and the user-input temperature to size on is #{OpenStudio.convert(htg_sizing_option_c, 'C', 'F').get.round(0)}F. User-input temperature is larger than design day temperature, so user-input temperature will be used.")
      else
        hp_sizing_temp_c = wntr_design_day_temp_c
        runner.registerInfo("For heat pump sizing, heating design day temperature is #{OpenStudio.convert(wntr_design_day_temp_c, 'C', 'F').get.round(0)}F, and the user-input temperature to size on is #{OpenStudio.convert(htg_sizing_option_c, 'C', 'F').get.round(0)}F. The heating design day temperature is higher than the user-specified temperature which is not realistic, therefore the heating design day temperature will be used.")
      end

      # define airflow stages - 4 equal segmenets from minimum airflow ratio to 100%
      # for systems with high OA flow fractions, this range may be very small
      # if the OA ratio is 100%, the unit will essentially act as a constant volume DOAS
      # heating stages
      htg_airflow_stage1 = min_airflow_m3_per_s
      htg_airflow_stage2 = htg_airflow_stage1 + 0.333 * (old_terminal_sa_flow_m3_per_s - htg_airflow_stage1)
      htg_airflow_stage3 = htg_airflow_stage2 + 0.333 * (old_terminal_sa_flow_m3_per_s - htg_airflow_stage2)
      htg_airflow_stage4 = old_terminal_sa_flow_m3_per_s
      hash_htg_airflow_stgs = {1 => htg_airflow_stage1, 2 => htg_airflow_stage2, 3 => htg_airflow_stage3, 4 => htg_airflow_stage4}
      # cooling stages
      clg_airflow_stage1 = htg_airflow_stage1
      clg_airflow_stage2 = htg_airflow_stage2
      clg_airflow_stage3 = htg_airflow_stage3
      clg_airflow_stage4 = htg_airflow_stage4
      hash_clg_airflow_stgs = {1 => clg_airflow_stage1, 2 => clg_airflow_stage2, 3 => clg_airflow_stage3, 4 => clg_airflow_stage4}

      # determine heating load curve; y=mx+b
      # assumes 0 load at 60F (15.556 C)
      htg_load_slope = (0 - orig_htg_coil_gross_cap) / (15.5556 - wntr_design_day_temp_c)
      htg_load_intercept = orig_htg_coil_gross_cap - (htg_load_slope * wntr_design_day_temp_c)

      # calculate heat pump design load, derate factors, and required rated capacities (at stage 4) for different OA temperatures; assumes 75F interior temp (23.8889C)
      ia_temp_c = 23.8889
      # design - temperature determined by design days in specified weather file
      oa_temp_c = wntr_design_day_temp_c
      dns_htg_load_at_dsn_temp = orig_htg_coil_gross_cap
      hp_derate_factor_at_dsn = 0.93607915412 + -0.005481563544*ia_temp_c + -8.5897908e-06*ia_temp_c**2 + 0.02491053192*oa_temp_c +5.3087076e-05*oa_temp_c**2 + -0.000155750364*ia_temp_c*oa_temp_c
      req_rated_hp_cap_at_47f_to_meet_load_at_dsn = dns_htg_load_at_dsn_temp / hp_derate_factor_at_dsn
      # 0F
      oa_temp_c = -17.7778
      dns_htg_load_at_0f = htg_load_slope*(-17.7778) + htg_load_intercept
      hp_derate_factor_at_0f = 0.93607915412 + -0.005481563544*ia_temp_c + -8.5897908e-06*ia_temp_c**2 + 0.02491053192*oa_temp_c + 5.3087076e-05*oa_temp_c**2 + -0.000155750364*ia_temp_c*oa_temp_c
      req_rated_hp_cap_at_47f_to_meet_load_at_0f = dns_htg_load_at_0f / hp_derate_factor_at_0f
      # 17F
      oa_temp_c = -8.33333
      dns_htg_load_at_17f = htg_load_slope*(-8.33333) + htg_load_intercept
      hp_derate_factor_at_17f = 0.93607915412 + -0.005481563544*ia_temp_c + -8.5897908e-06*ia_temp_c**2 + 0.02491053192*oa_temp_c + 5.3087076e-05*oa_temp_c**2 + -0.000155750364*ia_temp_c*oa_temp_c
      req_rated_hp_cap_at_47f_to_meet_load_at_17f = dns_htg_load_at_17f / hp_derate_factor_at_17f
      # 47F - note that this is rated conditions, so "derate" factor is either 1 from the curve, or will be normlized to 1 by E+ during simulation
      oa_temp_c = 8.33333
      dns_htg_load_at_47f = htg_load_slope*(-8.33333) + htg_load_intercept
      hp_derate_factor_at_47f = 1
      req_rated_hp_cap_at_47f_to_meet_load_at_47f = dns_htg_load_at_47f / hp_derate_factor_at_47f
      # user-specified design
      oa_temp_c = hp_sizing_temp_c
      dns_htg_load_at_user_dsn_temp = htg_load_slope*hp_sizing_temp_c + htg_load_intercept
      hp_derate_factor_at_user_dsn = 0.93607915412 + -0.005481563544*ia_temp_c + -8.5897908e-06*ia_temp_c**2 + 0.02491053192*oa_temp_c + 5.3087076e-05*oa_temp_c**2 + -0.000155750364*ia_temp_c*oa_temp_c
      req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn = dns_htg_load_at_user_dsn_temp / hp_derate_factor_at_user_dsn

      # determine heat pump system sizing based on user-specified sizing temperature and user-specified maximum upsizing limits
      # upsize total cooling capacity using user-specified factor
      autosized_tot_clg_cap_upsized = orig_clg_coil_gross_cap * clg_oversizing_estimate
      # get maximum cooling capacity with user-specified upsizing
      max_cool_cap_w_upsize = autosized_tot_clg_cap_upsized * (performance_oversizing_factor+1)
      # get maximum heating capacity based on max cooling capacity and heating-to-cooling ratio
      max_heat_cap_w_upsize = autosized_tot_clg_cap_upsized * (performance_oversizing_factor+1) * htg_to_clg_hp_ratio

      # set derate factor to 0 if less than 0F (-17.778 C)
      if wntr_design_day_temp_c < -17.7778
        hp_derate_factor_at_user_dsn = 0
      end
      
      # cooling capacity
      cool_cap = req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn / htg_to_clg_hp_ratio
      cool_cap_oversize_pct_actual = (((autosized_tot_clg_cap_upsized-cool_cap) / autosized_tot_clg_cap_upsized).abs() * 100).round(2)

      # If ratio of required heating capacity at rated conditions to cooling capacity is less than specified heating to cooling ratio, then size everything based on cooling
      if (req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn / autosized_tot_clg_cap_upsized) <=  htg_to_clg_hp_ratio
        # set rated heating capacity equal to upsized cooling capacity times the user-specified heating to cooling sizing ratio
        dx_rated_htg_cap_applied = autosized_tot_clg_cap_upsized * htg_to_clg_hp_ratio
        # set rated cooling capacity
        dx_rated_clg_cap_applied = autosized_tot_clg_cap_upsized
        # print register
        runner.registerInfo("For air loop #{air_loop_hvac.name}:
          >>Heating Sizing Information: Total heating requirement at design conditions is #{OpenStudio.convert(req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn, 'W', 'ton').get.round(2)} tons. User-input HP heating design temperature is #{OpenStudio.convert(hp_sizing_temp_c, 'C', 'F').get.round(0)}F, which yields a HP capacity derate factor of #{hp_derate_factor_at_user_dsn.round(2)} from the performance curve and a resulting heating capacity of #{OpenStudio.convert((req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn * hp_derate_factor_at_user_dsn), 'W', 'ton').get.round(2)} tons at #{OpenStudio.convert(hp_sizing_temp_c, 'C', 'F').get.round(0)}F. For the heat pump to meet the design heating load of #{OpenStudio.convert(req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn, 'W', 'ton').get.round(2)} tons at the design temperature of #{OpenStudio.convert(hp_sizing_temp_c, 'C', 'F').get.round(0)}F, the rated heat pump size (at 47F) must be greater than #{OpenStudio.convert(req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn, 'W', 'ton').get.round(2)} tons.
          >>Cooling Sizing Information: Total cooling requirement is #{OpenStudio.convert(orig_clg_coil_gross_cap, 'W', 'ton').get.round(2)} tons. The user-input cooling upsize factor to account for actual equipment selection is #{clg_oversizing_estimate}, resulting in a final total upsized cooling requirement of #{OpenStudio.convert(autosized_tot_clg_cap_upsized, 'W', 'ton').get.round(2)} tons.
          >>Sizing Limits: Increasing the HP total capacity to accomodate potential additional heating capacity is capped such that the resulting cooling capacity does not exceed the user-input oversizing factor of #{performance_oversizing_factor+1} times the required (upsized) cooling load of #{OpenStudio.convert(autosized_tot_clg_cap_upsized, 'W', 'ton').get.round(2)} tons. Therefore, the cooling capacity cannot exceed #{OpenStudio.convert(autosized_tot_clg_cap_upsized*(performance_oversizing_factor+1), 'W', 'ton').get.round(2)} tons, and to maintain the user-input heating to cooling ratio of #{htg_to_clg_hp_ratio}, the final hp heating capacity cannot exceed #{OpenStudio.convert(autosized_tot_clg_cap_upsized*(performance_oversizing_factor+1)*htg_to_clg_hp_ratio, 'W', 'ton').get.round(2)} tons.
          >>Sizing Results: Oversizing is not necessary as the design cooling capacity of #{OpenStudio.convert(autosized_tot_clg_cap_upsized, 'W', 'ton').get.round(2)} tons results in a heating capacity at rated condtions (47F) of #{OpenStudio.convert((autosized_tot_clg_cap_upsized * htg_to_clg_hp_ratio), 'W', 'ton').get.round(2)} tons and a derated heating capacity at the unser-input design temperature (#{OpenStudio.convert(hp_sizing_temp_c, 'C', 'F').get.round(0)}F) of #{OpenStudio.convert((autosized_tot_clg_cap_upsized * htg_to_clg_hp_ratio * hp_derate_factor_at_user_dsn), 'W', 'ton').get.round(2)} tons, which exceeds the design heating load requirement of #{OpenStudio.convert(req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn, 'W', 'ton').get.round(2)} tons. These values will be applied to the model as-is. For reference, the WEATHER FILE heating design day temperature of #{OpenStudio.convert(wntr_design_day_temp_c, 'C', 'F').get.round(0)}F yields a derate factor of #{hp_derate_factor_at_user_dsn.round(2)}, which results in a heating capacity of #{((autosized_tot_clg_cap_upsized * htg_to_clg_hp_ratio * hp_derate_factor_at_user_dsn)).get.round(2)} tons at this temperature, which is #{OpenStudio.convert(((autosized_tot_clg_cap_upsized * htg_to_clg_hp_ratio * hp_derate_factor_at_user_dsn) / req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn) * 100, 'W', 'ton').round(2)}% of the design heating load at this temperature.")
      # If heating load requires upsizing, but is below user-input cooling upsizing limit
      elsif req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn <= max_heat_cap_w_upsize
        # set rated heating coil equal to desired sized value, which should be below the suer-input limit
        dx_rated_htg_cap_applied = req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn
        # set cooling capacity to appropriate ratio based on heating capacity needs
        cool_cap = req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn / htg_to_clg_hp_ratio
        cool_cap_oversize_pct_actual = (((autosized_tot_clg_cap_upsized-cool_cap) / autosized_tot_clg_cap_upsized).abs() * 100).round(2)
        dx_rated_clg_cap_applied = cool_cap
        # print register
        runner.registerInfo("For air loop #{air_loop_hvac.name}:
          >>Heating Sizing Information: Total heating requirement at design conditions is #{OpenStudio.convert(req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn, 'W', 'ton').get.round(2)} tons. User-input HP heating design temperature is #{OpenStudio.convert(hp_sizing_temp_c, 'C', 'F').get.round(0)}F, which yields a HP capacity derate factor of #{hp_derate_factor_at_user_dsn.round(2)} from the performance curve and a resulting heating capacity of #{OpenStudio.convert((req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn * hp_derate_factor_at_user_dsn), 'W', 'ton').get.round(2)} tons at #{OpenStudio.convert(hp_sizing_temp_c, 'C', 'F').get.round(0)}F. For the heat pump to meet the design heating load of #{OpenStudio.convert(req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn, 'W', 'ton').get.round(2)} tons at the design temperature of #{OpenStudio.convert(hp_sizing_temp_c, 'C', 'F').get.round(0)}F, the rated heat pump size (at 47F) must be greater than #{OpenStudio.convert(req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn, 'W', 'ton').get.round(2)} tons. 
          >>Cooling Sizing Information: Total cooling requirement is #{OpenStudio.convert(orig_clg_coil_gross_cap, 'W', 'ton').get.round(2)} tons. The user-input cooling upsize factor to account for actual equipment selection is #{clg_oversizing_estimate}, resulting in a final total upsized cooling requirement of #{OpenStudio.convert(autosized_tot_clg_cap_upsized, 'W', 'ton').get.round(2)} tons.
          >>Sizing Limits: Increasing the HP total capacity to accomodate potential additional heating capacity is capped such that the resulting cooling capacity does not exceed the user-input oversizing factor of #{performance_oversizing_factor+1} times the required (upsized) cooling load of #{OpenStudio.convert(autosized_tot_clg_cap_upsized, 'W', 'ton').get.round(2)} tons. Therefore, the cooling capacity cannot exceed #{OpenStudio.convert(autosized_tot_clg_cap_upsized * (performance_oversizing_factor+1), 'W', 'ton').get.round(2)} tons, and to maintain the user-input heating to cooling ratio of #{htg_to_clg_hp_ratio}, the final hp heating capacity cannot exceed #{OpenStudio.convert(autosized_tot_clg_cap_upsized*(performance_oversizing_factor+1)*htg_to_clg_hp_ratio, 'W', 'ton').get.round(2)} tons.
          >>Sizing Results: To meet the design heating load of #{OpenStudio.convert((req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn), 'W', 'ton').get.round(2)} tons at #{OpenStudio.convert(hp_sizing_temp_c, 'C', 'F').get.round(0)}F}, the compressor will be oversized by #{cool_cap_oversize_pct_actual}% to a rated cooling capacity of #{OpenStudio.convert(cool_cap, 'W', 'ton').get.round(2)} tons and a rated heated capacity (at 47F) of #{OpenStudio.convert((req_rated_tot_htg_cap_at_47_f), 'W', 'ton').get.round(2)} tons. This oversizing is under the user-input limit of #{(performance_oversizing_factor*100).round(2)}% and is therefore permitted. For reference, the WEATHER FILE heating design day temperature of #{OpenStudio.convert(wntr_design_day_temp_c, 'C', 'F').get.round(0)}F yields a derate factor of #{hp_derate_factor_at_user_dsn.round(2)}, which results in a heating capacity of #{OpenStudio.convert((req_rated_tot_htg_cap_at_47_f * hp_derate_factor_at_user_dsn), 'W', 'ton').get.round(2)} tons at this temperature, which is #{(((req_rated_tot_htg_cap_at_47_f * hp_derate_factor_at_user_dsn) / req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn) * 100).get.round(2)}% of the design heating load at this temperature.")
      else
        # set rated heating capacity to maximum allowable based on cooling capacity maximum limit
        dx_rated_htg_cap_applied = max_cool_cap_w_upsize * htg_to_clg_hp_ratio
        # set rated cooling capacity to maximum allowable based on oversizing limit
        dx_rated_clg_cap_applied = max_cool_cap_w_upsize
        # print register
        runner.registerInfo("For air loop #{air_loop_hvac.name}:
          >>Heating Sizing Information: Total heating requirement at design conditions is #{OpenStudio.convert(req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn, 'W', 'ton').get.round(2)} tons. User-input HP heating design temperature is #{OpenStudio.convert(hp_sizing_temp_c, 'C', 'F').get.round(0)}F, which yields a HP capacity derate factor of #{hp_derate_factor_at_user_dsn.round(2)} from the performance curve and a resulting heating capacity of #{OpenStudio.convert((req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn * hp_derate_factor_at_user_dsn), 'W', 'ton').get.round(2)} tons at #{OpenStudio.convert(hp_sizing_temp_c, 'C', 'F').get.round(0)}F. For the heat pump to meet the design heating load of #{OpenStudio.convert(req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn, 'W', 'ton').get.round(2)} tons at the design temperature of #{OpenStudio.convert(hp_sizing_temp_c, 'C', 'F').get.round(0)}F, the rated heat pump size (at 47F) must be greater than #{OpenStudio.convert(req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn, 'W', 'ton').get.round(2)} tons.
          >>Cooling Sizing Information: Total cooling requirement is #{OpenStudio.convert(orig_clg_coil_gross_cap, 'W', 'ton').get.round(2)} tons. The user-input cooling upsize factor to account for actual equipment selection is #{clg_oversizing_estimate}, resulting in a final total upsized cooling requirement of #{OpenStudio.convert(autosized_tot_clg_cap_upsized, 'W', 'ton').get.round(2)} tons.
          >>Sizing Limits: Increasing the HP total capacity to accomodate potential additional heating capacity is capped such that the resulting cooling capacity does not exceed the user-input oversizing factor of #{performance_oversizing_factor+1} times the required (upsized) cooling load of #{OpenStudio.convert(autosized_tot_clg_cap_upsized, 'W', 'ton').get.round(2)} tons. Therefore, the cooling capacity cannot exceed #{OpenStudio.convert(autosized_tot_clg_cap_upsized * (performance_oversizing_factor+1), 'W', 'ton').get.round(2)} tons, and to maintain the user-input heating to cooling ratio of #{htg_to_clg_hp_ratio}, the final hp heating capacity cannot exceed #{OpenStudio.convert(autosized_tot_clg_cap_upsized*(performance_oversizing_factor+1)*htg_to_clg_hp_ratio, 'W', 'ton').get.round(2)} tons.
          >>Sizing Results: To meet the design heating load of #{OpenStudio.convert((req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn), 'W', 'ton').get.round(2)} tons at#{OpenStudio.convert(hp_sizing_temp_c, 'C', 'F').get.round(0)}F, the compressor needs to be oversized by #{cool_cap_oversize_pct_actual}%, which is beyond the user-input maximum value of #{(performance_oversizing_factor*100).round(2)}%. Therefore, the unit will be sized to the user-input maximum allowable, which results in a rated cooling capacity of#{OpenStudio.convert(max_cool_cap_w_upsize, 'W', 'ton').get.round(2)} tons, a rated heating capacity (at 47F) of #{OpenStudio.convert((max_cool_cap_w_upsize * htg_to_clg_hp_ratio), 'W', 'ton').get.round(2)} tons, and a heating capacity at design temperature(#{OpenStudio.convert(hp_sizing_temp_c, 'C', 'F').get.round(0)}F) of #{OpenStudio.convert(((max_cool_cap_w_upsize * htg_to_clg_hp_ratio) * hp_derate_factor_at_user_dsn), 'W', 'ton').get.round(2)} tons, which is #{((((max_cool_cap_w_upsize * htg_to_clg_hp_ratio) * hp_derate_factor_at_user_dsn) / (req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn))*100).round(2)}% of the design heating load at this temperature. For reference, the WEATHER FILE heating design day temperature of #{OpenStudio.convert(wntr_design_day_temp_c, 'C', 'F').get.round(0)}F yields a derate factor of#{hp_derate_factor_at_user_dsn.round(2)}, which results in a heating capacity of #{OpenStudio.convert((max_cool_cap_w_upsize * htg_to_clg_hp_ratio * hp_derate_factor_at_user_dsn), 'W', 'ton').get.round(2)} tons at this temperature, which is #{(((max_cool_cap_w_upsize * htg_to_clg_hp_ratio * hp_derate_factor_at_user_dsn) / req_rated_hp_cap_at_user_dsn_to_meet_load_at_user_dsn) * 100).round(2)}% of the design heating load at this temperature.")
      end
      ### Cooling
      # define cooling stages; 40% to 100%, equally spaced; fractions from ResStock Reference file
      clg_stage1 = dx_rated_clg_cap_applied * 0.36
      clg_stage2 = dx_rated_clg_cap_applied * 0.51
      clg_stage3 = dx_rated_clg_cap_applied * 0.67
      clg_stage4 = dx_rated_clg_cap_applied
      hash_clg_cap_stgs = {1 => clg_stage1, 2 => clg_stage2, 3 => clg_stage3, 4 => clg_stage4}

      # puts "Original Cooling..."
      # puts hash_clg_cap_stgs
      # puts hash_clg_airflow_stgs
      # puts ""

            ################################################
      # puts "Analysis..."
      hash_clg_speed_level_status = {}
      [4,3,2,1].each do |clg_stg|
        # define airflow and capacity for stage
        # puts "Stage #: #{clg_stg}"
        stg_cap = hash_clg_cap_stgs[clg_stg]
        # puts "Capacity: #{stg_cap}"
        stg_airflow = hash_clg_airflow_stgs[clg_stg]
        # puts "Airflow: #{stg_airflow}"
        ratio_flow_to_cap_orig = stg_airflow / stg_cap
        # puts "ratio_flow_to_cap_orig: #{ratio_flow_to_cap_orig}"
        # puts "Outdoor Air: #{oa_flow_m3_per_s}"
        
        # check upper limit of ratio for compliance (>450 CFM/Ton)
        spacer = 0 
        spacer = 1 unless clg_stg==4
        max_reached=false
        # next if clg_stg==4
        if ratio_flow_to_cap_orig > 0.00006041
          # range can be met using minimum airflow and increasing capacity of speed
          # this will only occur if new capacity is at least 50% between previous and new stage capacity
          if ((max_reached==false) && (((hash_clg_cap_stgs[clg_stg+spacer] - (stg_cap / (0.00006041 / (stg_airflow/stg_cap)))) / (hash_clg_cap_stgs[clg_stg+spacer] - stg_cap)) > 0.5)) || (clg_stg==4)
            # puts "cap changes"
            # puts ((hash_clg_cap_stgs[clg_stg+1] - (stg_cap / (0.00006041 / (oa_flow_m3_per_s/stg_cap)))) / (hash_clg_cap_stgs[clg_stg+1] - stg_cap))
            # max_reached=true
            # calculate new capacities based on decreased airflow to minimum allowed and increasing capacity
            new_airflow = stg_airflow
            new_cap = stg_cap / (0.00006041 / (stg_airflow/stg_cap))
            hash_clg_airflow_stgs[clg_stg] = new_airflow
            hash_clg_cap_stgs[clg_stg] = new_cap
            runner.registerWarning("For airloop #{air_loop_hvac.name}, cooling stage #{clg_stg} airflow/capacity ratio is too high with a value of #{(ratio_flow_to_cap_orig).round(8)} m3/s/watt, which exceeds the maximum allowable value of 6.041e-05 m3/s/watt. The capacity of the stage will be increased from #{stg_cap.round(0)} watts to #{new_cap.round(0)} watts.")
            hash_clg_speed_level_status[clg_stg] = true
            # puts new_airflow
            # puts new_cap
            # puts new_airflow/new_cap
          # range cannot be met given minimum airflow constraints, or limit has already been met in previous stage
          else
            max_reached=true
            runner.registerWarning("For airloop #{air_loop_hvac.name}, cooling stage #{clg_stg} airflow/capacity airflow is too high with a value of #{(ratio_flow_to_cap_orig).round(8)} m3/s/watt, which exceeds the maximum allowable value of 6.04e-05 m3/s/watt. Due to minimum outdoor airflow requirements this value cannot be brought into bounds. This stage will be given a neglible capacity making it effectively unavailable.")
            hash_clg_speed_level_status[clg_stg] = false
          end

        # check lower limit of ratio for complaince (<300 CFM/Ton)
        elsif ((stg_airflow / stg_cap) < 0.00004027) && (clg_stg != 4)
          # calculate new stage capacity to fall in range. This should be an increase.
          new_cap = stg_cap / (0.00004027 / (stg_airflow/stg_cap))
          hash_clg_cap_stgs[clg_stg] = new_cap
          runner.registerWarning("For airloop #{air_loop_hvac.name}, cooling stage #{clg_stg} airflow/capacity ratio is too low with a value of #{(ratio_flow_to_cap_orig).round(8)} m3/s/watt, which exceeds the maximum allowable value of 4.03e-05 m3/s/watt. The capacity for this stage will be decreased from #{stg_cap.round(2)} watts to #{new_cap.round(2)} m3/s to bring the airflow/capacity within the allowable bounds.")
          hash_clg_speed_level_status[clg_stg] = true
        else
          hash_clg_speed_level_status[clg_stg] = true
        end
      end

      # puts ""
      # puts "New Cooling"
      # puts hash_clg_cap_stgs
      # puts hash_clg_airflow_stgs
      # puts hash_clg_speed_level_status
      # puts ""

      ### Heating
      # define heating stages
      htg_stage1 = dx_rated_htg_cap_applied * 0.28
      htg_stage2 = dx_rated_htg_cap_applied * 0.48
      htg_stage3 = dx_rated_htg_cap_applied * 0.85
      htg_stage4 = dx_rated_htg_cap_applied
      hash_htg_cap_stgs = {1 => htg_stage1, 2 => htg_stage2, 3 => htg_stage3, 4 => htg_stage4}

      # puts "Original Heating..."
      # puts hash_htg_cap_stgs
      # puts hash_htg_airflow_stgs
      # puts ""

      max_reached=false
      hash_htg_speed_level_status = {}
      [4,3,2,1].each do |htg_stg|
        # puts htg_stg
        # define airflow and capacity for stage
        # puts "Stage #: #{htg_stg}"
        stg_cap = hash_htg_cap_stgs[htg_stg]
        # puts "Capacity: #{stg_cap}"
        stg_airflow = hash_htg_airflow_stgs[htg_stg]
        # puts "Airflow: #{stg_airflow}"
        ratio_flow_to_cap_orig = stg_airflow / stg_cap
        # puts "ratio_flow_to_cap_orig: #{ratio_flow_to_cap_orig}"
        # puts "Outdoor Air: #{oa_flow_m3_per_s}"
        
        # check upper limit of ratio for compliance (>450 CFM/Ton)
        spacer = 0 
        spacer = 1 unless htg_stg==4
        # next if htg_stg==4
        if ratio_flow_to_cap_orig > 0.00006041
          # puts "Flow too high"
          # range can be met using minimum airflow and increasing capacity of speed
          # this will only occur if new capacity is at least 50% between previous and new stage capacity
          if ((max_reached==false) && (((hash_htg_cap_stgs[htg_stg+spacer] - (stg_cap / (0.00006041 / (stg_airflow/stg_cap)))) / (hash_htg_cap_stgs[htg_stg+spacer] - stg_cap)) > 0.5)) || (htg_stg==4)
            # max_reached=true
            # calculate new capacities based on decreased airflow to minimum allowed and increasing capacity
            new_airflow = stg_airflow
            new_cap = stg_cap / (0.00006041 / (stg_airflow/stg_cap))
            hash_htg_airflow_stgs[htg_stg] = new_airflow
            hash_htg_cap_stgs[htg_stg] = new_cap
            runner.registerWarning("For airloop #{air_loop_hvac.name}, heating stage #{htg_stg} airflow/capacity ratio is too high with a value of #{(ratio_flow_to_cap_orig).round(8)} m3/s/watt, which exceeds the maximum allowable value of 6.04e-05 m3/s/watt. The capacity of the stage will be increased from #{stg_cap.round(0)} watts to #{new_cap.round(0)} watts.")
            hash_htg_speed_level_status[htg_stg] = true
            # puts new_airflow
            # puts new_cap
            # puts new_airflow/new_cap
          # range cannot be met given minimum airflow constraints, or limit has already been met in previous stage
          else
            # puts "cant help"
            max_reached=true
            runner.registerWarning("For airloop #{air_loop_hvac.name}, heating stage #{htg_stg} airflow/capacity airflow is too high with a value of #{(ratio_flow_to_cap_orig).round(8)} m3/s/watt, which exceeds the maximum allowable value of 6.04e-05 m3/s/watt. Due to minimum outdoor airflow requirements this value cannot be brought into bounds. This stage will be given a neglible capacity making it effectively unavailable.")
            hash_htg_speed_level_status[htg_stg] = false
          end

        # check lower limit of ratio for complaince (<300 CFM/Ton)
        # check lower limit of ratio for complaince (<300 CFM/Ton)
        elsif ((stg_airflow / stg_cap) < 0.00004027) && (htg_stg != 4)
          # calculate new stage capacity to fall in range. This should be an increase.
          new_cap = stg_cap / (0.00004027 / (stg_airflow/stg_cap))
          hash_htg_cap_stgs[htg_stg] = new_cap
          runner.registerWarning("For airloop #{air_loop_hvac.name}, heating stage #{htg_stg} airflow/capacity ratio is too low with a value of #{(ratio_flow_to_cap_orig).round(8)} m3/s/watt, which exceeds the maximum allowable value of 4.03e-05 m3/s/watt. The capacity for this stage will be decreased from #{stg_cap.round(2)} watts to #{new_cap.round(2)} m3/s to bring the airflow/capacity within the allowable bounds.")
          hash_htg_speed_level_status[htg_stg] = true
        else
          hash_htg_speed_level_status[htg_stg] = true
        end
      end

      # puts ""
      # puts "New Heating"
      # puts hash_htg_cap_stgs
      # puts hash_htg_airflow_stgs
      # puts hash_htg_speed_level_status
      ###############################################



      # ################################################
      # # puts "Analysis..."
      # max_reached=false
      # hash_clg_speed_level_status = {}
      # [4,3,2,1].each do |clg_stg|
      #   # define airflow and capacity for stage
      #   # puts "Stage #: #{clg_stg}"
      #   stg_cap = hash_clg_cap_stgs[clg_stg]
      #   # puts "Capacity: #{stg_cap}"
      #   stg_airflow = hash_clg_airflow_stgs[clg_stg]
      #   # puts "Airflow: #{stg_airflow}"
      #   ratio_flow_to_cap_orig = stg_airflow / stg_cap
      #   # puts "ratio_flow_to_cap_orig: #{ratio_flow_to_cap_orig}"
      #   # puts "Outdoor Air: #{oa_flow_m3_per_s}"
        
      #   # check upper limit of ratio for compliance (>450 CFM/Ton)
      #   # next if clg_stg==4
      #   if ratio_flow_to_cap_orig > 0.00006041
      #     # range can be satisfied by lowering airflow rate only
      #     if (0.00006041/ratio_flow_to_cap_orig)*stg_airflow > oa_flow_m3_per_s
      #       new_airflow = (0.00006041/ratio_flow_to_cap_orig)*stg_airflow
      #       runner.registerWarning("Cooling stage #{clg_stg} airflow/capacity ratio is too high with a value of #{(ratio_flow_to_cap_orig).round(7)} m3/s/watt, which exceeds the maximum allowable value of 6.04e-05 m3/s/watt. The airflow for this stage will be decreased from #{stg_airflow.round(2)} m3/s to #{new_airflow.round(2)} m3/s to bring the airflow/capacity within the allowable bounds.")
      #       # calculate new stage airflow
      #       hash_clg_airflow_stgs[clg_stg] = new_airflow
      #       hash_clg_speed_level_status[clg_stg] = true
      #     # range can be met using minimum airflow and increasing capacity of speed
      #     # this will only occur if new capacity is at least 50% between previous and new stage capacity
      #     elsif (max_reached==false) && (((hash_clg_cap_stgs[clg_stg+1] - (stg_cap / (0.00006041 / (oa_flow_m3_per_s/stg_cap)))) / (hash_clg_cap_stgs[clg_stg+1] - stg_cap)) > 0.5)
      #       # puts "cap changes"
      #       # puts ((hash_clg_cap_stgs[clg_stg+1] - (stg_cap / (0.00006041 / (oa_flow_m3_per_s/stg_cap)))) / (hash_clg_cap_stgs[clg_stg+1] - stg_cap))
      #       max_reached=true
      #       # calculate new capacities based on decreased airflow to minimum allowed and increasing capacity
      #       new_airflow = oa_flow_m3_per_s
      #       new_cap = stg_cap / (0.00006041 / (oa_flow_m3_per_s/stg_cap))
      #       hash_clg_airflow_stgs[clg_stg] = new_airflow
      #       hash_clg_cap_stgs[clg_stg] = new_cap
      #       runner.registerWarning("Cooling stage #{clg_stg} airflow/capacity ratio is too high with a value of #{(ratio_flow_to_cap_orig).round(7)} m3/s/watt, which exceeds the maximum allowable value of 6.04e-05 m3/s/watt. The airflow for this stage will be decreased from #{stg_airflow.round(2)} m3/s to the minimum allowable of #{oa_flow_m3_per_s.round(2)} m3/s, and the capacity of the stage will be increased from #{stg_cap.round(0)} watts to #{new_cap.round(0)} watts.")
      #       hash_clg_speed_level_status[clg_stg] = true
      #       # puts new_airflow
      #       # puts new_cap
      #       # puts new_airflow/new_cap
      #     # range cannot be met given minimum airflow constraints, or limit has already been met in previous stage
      #     else
      #       max_reached=true
      #       runner.registerWarning("Cooling stage #{clg_stg} airflow/capacity airflow is too high with a value of #{(ratio_flow_to_cap_orig).round(7)} m3/s/watt, which exceeds the maximum allowable value of 6.04e-05 m3/s/watt. Due to minimum outdoor airflow requirements this value cannot be brought into bounds. This stage will be given a neglible capacity making it effectively unavailable.")
      #       hash_clg_airflow_stgs[clg_stg] = hash_clg_airflow_stgs[clg_stg+1]
      #       hash_clg_cap_stgs[clg_stg] = clg_stg # very small capacity differentiated from others by just using the speed number as the wattage
      #       hash_clg_speed_level_status[clg_stg] = false
      #     end

      #   # check lower limit of ratio for complaince (<300 CFM/Ton)
      #   elsif (stg_airflow / stg_cap) < 0.00004027

      #     # calculate airflow increase needed to bring stage airflow above minimum limit
      #     new_airflow = (0.00004027/ratio_flow_to_cap_orig)*stg_airflow

      #     # apply airflow so long as it does not exceed the airflow of the stage above it
      #     if new_airflow <= hash_clg_airflow_stgs[clg_stg+1]
      #       hash_clg_airflow_stgs[clg_stg] = new_airflow
      #       runner.registerWarning("Cooling stage #{clg_stg} airflow/capacity ratio is too low with a value of #{(ratio_flow_to_cap_orig).round(7)} m3/s/watt, which exceeds the maximum allowable value of 4.03e-05 m3/s/watt. The airflow for this stage will be increased from #{stg_airflow.round(2)} m3/s to #{new_airflow.round(2)} m3/s to bring the airflow/capacity within the allowable bounds.")
      #     else
      #       runner.registerError("Cooling stage #{clg_stg} airflow/capacity ratio is too low with a value of #{(ratio_flow_to_cap_orig).round(7)} m3/s/watt, which exceeds the maximum allowable value of 4.03e-05 m3/s/watt. This value cannot be brought into bounds without increasing the airflow limit beyond that of a higher stage, which in not permittible. Please revise model accordingly.")
      #     end
      #   else
      #     hash_clg_speed_level_status[clg_stg] = true

      #   end
      # end

      # puts ""
      # puts "New Cooling"
      # puts hash_clg_cap_stgs
      # puts hash_clg_airflow_stgs
      # puts hash_clg_speed_level_status

      # ### Heating
      # # define heating stages
      # htg_stage1 = dx_rated_htg_cap_applied * 0.28
      # htg_stage2 = dx_rated_htg_cap_applied * 0.48
      # htg_stage3 = dx_rated_htg_cap_applied * 0.85
      # htg_stage4 = dx_rated_htg_cap_applied
      # hash_htg_cap_stgs = {1 => htg_stage1, 2 => htg_stage2, 3 => htg_stage3, 4 => htg_stage4}

      # puts "Original Heating..."
      # puts hash_htg_cap_stgs
      # puts hash_htg_airflow_stgs
      # puts ""

      # max_reached=false
      # hash_htg_speed_level_status = {}
      # [4,3,2,1].each do |htg_stg|
      #   # define airflow and capacity for stage
      #   # puts "Stage #: #{htg_stg}"
      #   stg_cap = hash_htg_cap_stgs[htg_stg]
      #   # puts "Capacity: #{stg_cap}"
      #   stg_airflow = hash_htg_airflow_stgs[htg_stg]
      #   # puts "Airflow: #{stg_airflow}"
      #   ratio_flow_to_cap_orig = stg_airflow / stg_cap
      #   # puts "ratio_flow_to_cap_orig: #{ratio_flow_to_cap_orig}"
      #   # puts "Outdoor Air: #{oa_flow_m3_per_s}"
        
      #   # check upper limit of ratio for compliance (>450 CFM/Ton)
      #   # next if htg_stg==4
      #   if ratio_flow_to_cap_orig > 0.00006041
      #     # range can be satisfied by lowering airflow rate only
      #     if (0.00006041/ratio_flow_to_cap_orig)*stg_airflow > oa_flow_m3_per_s
      #       new_airflow = (0.00006041/ratio_flow_to_cap_orig)*stg_airflow
      #       runner.registerWarning("Heating stage #{htg_stg} airflow/capacity ratio is too high with a value of #{(ratio_flow_to_cap_orig).round(7)} m3/s/watt, which exceeds the maximum allowable value of 6.04e-05 m3/s/watt. The airflow for this stage will be decreased from #{stg_airflow.round(2)} m3/s to #{new_airflow.round(2)} m3/s to bring the airflow/capacity within the allowable bounds.")
      #       # calculate new stage airflow
      #       hash_htg_airflow_stgs[htg_stg] = new_airflow
      #       hash_htg_speed_level_status[htg_stg] = true
      #     # range can be met using minimum airflow and increasing capacity of speed
      #     # this will only occur if new capacity is at least 50% between previous and new stage capacity
      #     elsif (max_reached==false) && (((hash_htg_cap_stgs[htg_stg+1] - (stg_cap / (0.00006041 / (oa_flow_m3_per_s/stg_cap)))) / (hash_htg_cap_stgs[htg_stg+1] - stg_cap)) > 0.5)
      #       # puts "cap changes"
      #       # puts ((hash_clg_cap_stgs[clg_stg+1] - (stg_cap / (0.00006041 / (oa_flow_m3_per_s/stg_cap)))) / (hash_clg_cap_stgs[clg_stg+1] - stg_cap))
      #       max_reached=true
      #       # calculate new capacities based on decreased airflow to minimum allowed and increasing capacity
      #       new_airflow = oa_flow_m3_per_s
      #       new_cap = stg_cap / (0.00006041 / (oa_flow_m3_per_s/stg_cap))
      #       hash_htg_airflow_stgs[htg_stg] = new_airflow
      #       hash_htg_cap_stgs[htg_stg] = new_cap
      #       runner.registerWarning("Heating stage #{htg_stg} airflow/capacity ratio is too high with a value of #{(ratio_flow_to_cap_orig).round(7)} m3/s/watt, which exceeds the maximum allowable value of 6.04e-05 m3/s/watt. The airflow for this stage will be decreased from #{stg_airflow.round(2)} m3/s to the minimum allowable of #{oa_flow_m3_per_s.round(2)} m3/s, and the capacity of the stage will be increased from #{stg_cap.round(0)} watts to #{new_cap.round(0)} watts.")
      #       hash_htg_speed_level_status[htg_stg] = true
      #       # puts new_airflow
      #       # puts new_cap
      #       # puts new_airflow/new_cap
      #     # range cannot be met given minimum airflow constraints, or limit has already been met in previous stage
      #     else
      #       max_reached=true
      #       runner.registerWarning("Heating stage #{htg_stg} airflow/capacity airflow is too high with a value of #{(ratio_flow_to_cap_orig).round(7)} m3/s/watt, which exceeds the maximum allowable value of 6.04e-05 m3/s/watt. Due to minimum outdoor airflow requirements this value cannot be brought into bounds. This stage will be given a neglible capacity making it effectively unavailable.")
      #       hash_htg_airflow_stgs[htg_stg] = hash_htg_airflow_stgs[htg_stg+1]
      #       hash_htg_cap_stgs[htg_stg] = htg_stg # very small capacity differentiated from others by just using the speed number as the wattage
      #       hash_htg_speed_level_status[htg_stg] = false
      #     end

      #   # check lower limit of ratio for complaince (<300 CFM/Ton)
      #   elsif (stg_airflow / stg_cap) < 0.00004027

      #     # calculate airflow increase needed to bring stage airflow above minimum limit
      #     new_airflow = (0.00004027/ratio_flow_to_cap_orig)*stg_airflow

      #     # apply airflow so long as it does not exceed the airflow of the stage above it
      #     if new_airflow <= hash_htg_airflow_stgs[htg_stg+1]
      #       hash_htg_airflow_stgs[htg_stg] = new_airflow
      #       runner.registerWarning("Heating stage #{htg_stg} airflow/capacity ratio is too low with a value of #{(ratio_flow_to_cap_orig).round(7)} m3/s/watt, which exceeds the maximum allowable value of 4.03e-05 m3/s/watt. The airflow for this stage will be increased from #{stg_airflow.round(2)} m3/s to #{new_airflow.round(2)} m3/s to bring the airflow/capacity within the allowable bounds.")
      #     else
      #       runner.registerError("Heating stage #{htg_stg} airflow/capacity ratio is too low with a value of #{(ratio_flow_to_cap_orig).round(7)} m3/s/watt, which exceeds the maximum allowable value of 4.03e-05 m3/s/watt. This value cannot be brought into bounds without increasing the airflow limit beyond that of a higher stage, which in not permittible. Please revise model accordingly.")
      #     end
      #   else
      #     hash_htg_speed_level_status[htg_stg] = true
      #   end
      # end

      # puts ""
      # puts "New Heating"
      # puts hash_htg_cap_stgs
      # puts hash_htg_airflow_stgs
      # puts hash_htg_speed_level_status
      # ###############################################

      #################################### End Sizing Logic

      ################################### Cooling Performance Curves
      # define performance curves

      # Cooling Capacity Function of Temperature Curve - 1
      cool_cap_ft1 = OpenStudio::Model::CurveBiquadratic.new(model)
      cool_cap_ft1.setName("#{air_loop_hvac.name} cool_cap_ft1")
      cool_cap_ft1.setCoefficient1Constant(1.203)
      cool_cap_ft1.setCoefficient2x(0.07866)
      cool_cap_ft1.setCoefficient3xPOW2(-0.001797)
      cool_cap_ft1.setCoefficient4y(-0.09527)
      cool_cap_ft1.setCoefficient5yPOW2(0.00134)
      cool_cap_ft1.setCoefficient6xTIMESY(0.0009421)
      cool_cap_ft1.setMinimumValueofx(-100)
      cool_cap_ft1.setMaximumValueofx(100)
      cool_cap_ft1.setMinimumValueofy(-100)
      cool_cap_ft1.setMaximumValueofy(100)
      # Heating Capacity Function of Temperature Curve - 2
      cool_cap_ft2 = OpenStudio::Model::CurveBiquadratic.new(model)
      cool_cap_ft2.setName("#{air_loop_hvac.name} cool_cap_ft2")
      cool_cap_ft2.setCoefficient1Constant(-1.07)
      cool_cap_ft2.setCoefficient2x(0.2633)
      cool_cap_ft2.setCoefficient3xPOW2(-0.00629)
      cool_cap_ft2.setCoefficient4y(-0.03907)
      cool_cap_ft2.setCoefficient5yPOW2(0.0005085)
      cool_cap_ft2.setCoefficient6xTIMESY(0.0001078)
      cool_cap_ft2.setMinimumValueofx(-100)
      cool_cap_ft2.setMaximumValueofx(100)
      cool_cap_ft2.setMinimumValueofy(-100)
      cool_cap_ft2.setMaximumValueofy(100)
      # Heating Capacity Function of Temperature Curve - 3
      cool_cap_ft3 = OpenStudio::Model::CurveBiquadratic.new(model)
      cool_cap_ft3.setName("#{air_loop_hvac.name} cool_cap_ft3")
      cool_cap_ft3.setCoefficient1Constant(-0.619499999999998)
      cool_cap_ft3.setCoefficient2x(0.1621)
      cool_cap_ft3.setCoefficient3xPOW2(-0.003028)
      cool_cap_ft3.setCoefficient4y(-0.002812)
      cool_cap_ft3.setCoefficient5yPOW2(-2.59e-05)
      cool_cap_ft3.setCoefficient6xTIMESY(-0.0003764)
      cool_cap_ft3.setMinimumValueofx(-100)
      cool_cap_ft3.setMaximumValueofx(100)
      cool_cap_ft3.setMinimumValueofy(-100)
      cool_cap_ft3.setMaximumValueofy(100)
      # Heating Capacity Function of Temperature Curve - 4
      cool_cap_ft4 = OpenStudio::Model::CurveBiquadratic.new(model)
      cool_cap_ft4.setName("#{air_loop_hvac.name} cool_cap_ft4")
      cool_cap_ft4.setCoefficient1Constant(1.037)
      cool_cap_ft4.setCoefficient2x(-0.02036)
      cool_cap_ft4.setCoefficient3xPOW2(0.002231)
      cool_cap_ft4.setCoefficient4y(-0.000253799999999998)
      cool_cap_ft4.setCoefficient5yPOW2(4.604e-05)
      cool_cap_ft4.setCoefficient6xTIMESY(-0.000779)
      cool_cap_ft4.setMinimumValueofx(-100)
      cool_cap_ft4.setMaximumValueofx(100)
      cool_cap_ft4.setMinimumValueofy(-100)
      cool_cap_ft4.setMaximumValueofy(100)

      # Heating Capacity Function of Flow Fraction Curve
      cool_cap_fff_all_stages = OpenStudio::Model::CurveQuadratic.new(model)
      cool_cap_fff_all_stages.setName("#{air_loop_hvac.name} cool_cap_fff_all_stages")
      cool_cap_fff_all_stages.setCoefficient1Constant(1)
      cool_cap_fff_all_stages.setCoefficient2x(0)
      cool_cap_fff_all_stages.setCoefficient3xPOW2(0)
      cool_cap_fff_all_stages.setMinimumValueofx(0)
      cool_cap_fff_all_stages.setMaximumValueofx(2)
      cool_cap_fff_all_stages.setMinimumCurveOutput(0)
      cool_cap_fff_all_stages.setMaximumCurveOutput(2)

      # Energy Input Ratio Function of Temperature Curve - 1
      cool_eir_ft1 = OpenStudio::Model::CurveBiquadratic.new(model)
      cool_eir_ft1.setName("#{air_loop_hvac.name} cool_eir_ft1")
      cool_eir_ft1.setCoefficient1Constant(1.021)
      cool_eir_ft1.setCoefficient2x(-0.1214)
      cool_eir_ft1.setCoefficient3xPOW2(0.003936)
      cool_eir_ft1.setCoefficient4y(0.05435)
      cool_eir_ft1.setCoefficient5yPOW2(0.000283)
      cool_eir_ft1.setCoefficient6xTIMESY(-0.002057)
      cool_eir_ft1.setMinimumValueofx(-100)
      cool_eir_ft1.setMaximumValueofx(100)
      cool_eir_ft1.setMinimumValueofy(-100)
      cool_eir_ft1.setMaximumValueofy(100)
      # Energy Input Ratio Function of Temperature Curve - 2
      cool_eir_ft2 = OpenStudio::Model::CurveBiquadratic.new(model)
      cool_eir_ft2.setName("#{air_loop_hvac.name} cool_eir_ft2")
      cool_eir_ft2.setCoefficient1Constant(1.999)
      cool_eir_ft2.setCoefficient2x(-0.1977)
      cool_eir_ft2.setCoefficient3xPOW2(0.006001)
      cool_eir_ft2.setCoefficient4y(0.03196)
      cool_eir_ft2.setCoefficient5yPOW2(0.000638)
      cool_eir_ft2.setCoefficient6xTIMESY(-0.001948)
      cool_eir_ft2.setMinimumValueofx(-100)
      cool_eir_ft2.setMaximumValueofx(100)
      cool_eir_ft2.setMinimumValueofy(-100)
      cool_eir_ft2.setMaximumValueofy(100)
      # Energy Input Ratio Function of Temperature Curve - 3
      cool_eir_ft3 = OpenStudio::Model::CurveBiquadratic.new(model)
      cool_eir_ft3.setName("#{air_loop_hvac.name} cool_eir_ft3")
      cool_eir_ft3.setCoefficient1Constant(1.745)
      cool_eir_ft3.setCoefficient2x(-0.1546)
      cool_eir_ft3.setCoefficient3xPOW2(0.004585)
      cool_eir_ft3.setCoefficient4y(0.02595)
      cool_eir_ft3.setCoefficient5yPOW2(0.0006609)
      cool_eir_ft3.setCoefficient6xTIMESY(-0.001752)
      cool_eir_ft3.setMinimumValueofx(-100)
      cool_eir_ft3.setMaximumValueofx(100)
      cool_eir_ft3.setMinimumValueofy(-100)
      cool_eir_ft3.setMaximumValueofy(100)
      # Energy Input Ratio Function of Temperature Curve - 4
      cool_eir_ft4 = OpenStudio::Model::CurveBiquadratic.new(model)
      cool_eir_ft4.setName("#{air_loop_hvac.name} cool_eir_ft4")
      cool_eir_ft4.setCoefficient1Constant(0.2555)
      cool_eir_ft4.setCoefficient2x(0.03711)
      cool_eir_ft4.setCoefficient3xPOW2(-0.001427)
      cool_eir_ft4.setCoefficient4y(0.008907)
      cool_eir_ft4.setCoefficient5yPOW2(0.0005665)
      cool_eir_ft4.setCoefficient6xTIMESY(-0.0006538)
      cool_eir_ft4.setMinimumValueofx(-100)
      cool_eir_ft4.setMaximumValueofx(100)
      cool_eir_ft4.setMinimumValueofy(-100)
      cool_eir_ft4.setMaximumValueofy(100)

      # Energy Input Ratio Function of Flow Fraction Curve
      cool_eir_fff_all_stages = OpenStudio::Model::CurveQuadratic.new(model)
      cool_eir_fff_all_stages.setName("#{air_loop_hvac.name} cool_eir_fff")
      cool_eir_fff_all_stages.setCoefficient1Constant(1)
      cool_eir_fff_all_stages.setCoefficient2x(0)
      cool_eir_fff_all_stages.setCoefficient3xPOW2(0)
      cool_eir_fff_all_stages.setMinimumValueofx(0)
      cool_eir_fff_all_stages.setMaximumValueofx(2)
      cool_eir_fff_all_stages.setMinimumCurveOutput(0)
      cool_eir_fff_all_stages.setMaximumCurveOutput(2)

      # Part Load Fraction Correlation Curve
      cool_plf_fplr_all_stages = OpenStudio::Model::CurveQuadratic.new(model)
      cool_plf_fplr_all_stages.setName("#{air_loop_hvac.name} cool_plf_fplr")
      cool_plf_fplr_all_stages.setCoefficient1Constant(0.75)
      cool_plf_fplr_all_stages.setCoefficient2x(0.25)
      cool_plf_fplr_all_stages.setCoefficient3xPOW2(0)
      cool_plf_fplr_all_stages.setMinimumValueofx(0)
      cool_plf_fplr_all_stages.setMaximumValueofx(1)
      cool_plf_fplr_all_stages.setMinimumCurveOutput(0.7)
      cool_plf_fplr_all_stages.setMaximumCurveOutput(1)

      # add new multispeed cooling coil
      new_dx_cooling_coil = OpenStudio::Model::CoilCoolingDXMultiSpeed.new(model)
      new_dx_cooling_coil.setName("#{air_loop_hvac.name} Heat Pump Cooling Coil")
      new_dx_cooling_coil.setCondenserType('AirCooled')
      new_dx_cooling_coil.setAvailabilitySchedule(always_on)
      new_dx_cooling_coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(-25)
      new_dx_cooling_coil.setApplyPartLoadFractiontoSpeedsGreaterthan1(false)
      new_dx_cooling_coil.setApplyLatentDegradationtoSpeedsGreaterthan1(false)
      new_dx_cooling_coil.setFuelType('Electricity')

      # add stage data
      # create stage 1
      new_dx_cooling_coil_speed1 = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
      new_dx_cooling_coil_speed1.setGrossRatedTotalCoolingCapacity(hash_clg_cap_stgs[1])
      new_dx_cooling_coil_speed1.setGrossRatedSensibleHeatRatio(0.872821200315651)
      new_dx_cooling_coil_speed1.setGrossRatedCoolingCOP(4.40)
      new_dx_cooling_coil_speed1.setRatedAirFlowRate(hash_clg_airflow_stgs[1])
      new_dx_cooling_coil_speed1.setRatedEvaporatorFanPowerPerVolumeFlowRate(773.3)
      new_dx_cooling_coil_speed1.setTotalCoolingCapacityFunctionofTemperatureCurve(cool_cap_ft1)
      new_dx_cooling_coil_speed1.setTotalCoolingCapacityFunctionofFlowFractionCurve(cool_cap_fff_all_stages)
      new_dx_cooling_coil_speed1.setEnergyInputRatioFunctionofTemperatureCurve(cool_eir_ft1)
      new_dx_cooling_coil_speed1.setEnergyInputRatioFunctionofFlowFractionCurve (cool_eir_fff_all_stages)
      new_dx_cooling_coil_speed1.setPartLoadFractionCorrelationCurve(cool_plf_fplr_all_stages)
      new_dx_cooling_coil_speed1.setNominalTimeforCondensateRemovaltoBegin(1000)
      new_dx_cooling_coil_speed1.setRatioofInitialMoistureEvaporationRateandSteadyStateLatentCapacity(1.5)
      new_dx_cooling_coil_speed1.setLatentCapacityTimeConstant(45)
      new_dx_cooling_coil_speed1.setEvaporativeCondenserEffectiveness(0.9)
      new_dx_cooling_coil_speed1.autosizedEvaporativeCondenserAirFlowRate
      new_dx_cooling_coil_speed1.autosizedRatedEvaporativeCondenserPumpPowerConsumption
      new_dx_cooling_coil.addStage(new_dx_cooling_coil_speed1) unless ((hash_clg_speed_level_status[1] == false) || (hash_htg_speed_level_status[1] == false))

      # create stage 2
      new_dx_cooling_coil_speed2 = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
      new_dx_cooling_coil_speed2.setGrossRatedTotalCoolingCapacity(hash_clg_cap_stgs[2])
      new_dx_cooling_coil_speed2.setGrossRatedSensibleHeatRatio(0.80463149283227)
      new_dx_cooling_coil_speed2.setGrossRatedCoolingCOP(4.56)
      new_dx_cooling_coil_speed2.setRatedAirFlowRate(hash_clg_airflow_stgs[2])
      new_dx_cooling_coil_speed2.setRatedEvaporatorFanPowerPerVolumeFlowRate(773.3)
      new_dx_cooling_coil_speed2.setTotalCoolingCapacityFunctionofTemperatureCurve(cool_cap_ft2)
      new_dx_cooling_coil_speed2.setTotalCoolingCapacityFunctionofFlowFractionCurve(cool_cap_fff_all_stages)
      new_dx_cooling_coil_speed2.setEnergyInputRatioFunctionofTemperatureCurve(cool_eir_ft2)
      new_dx_cooling_coil_speed2.setEnergyInputRatioFunctionofFlowFractionCurve (cool_eir_fff_all_stages)
      new_dx_cooling_coil_speed2.setPartLoadFractionCorrelationCurve(cool_plf_fplr_all_stages)
      new_dx_cooling_coil_speed2.setNominalTimeforCondensateRemovaltoBegin(1000)
      new_dx_cooling_coil_speed2.setRatioofInitialMoistureEvaporationRateandSteadyStateLatentCapacity(1.5)
      new_dx_cooling_coil_speed2.setLatentCapacityTimeConstant(45)
      new_dx_cooling_coil_speed2.setEvaporativeCondenserEffectiveness(0.9)
      new_dx_cooling_coil_speed2.autosizedEvaporativeCondenserAirFlowRate
      new_dx_cooling_coil_speed2.autosizedRatedEvaporativeCondenserPumpPowerConsumption
      new_dx_cooling_coil.addStage(new_dx_cooling_coil_speed2) unless ((hash_clg_speed_level_status[2] == false) || (hash_htg_speed_level_status[2] == false))

      # create stage 3
      new_dx_cooling_coil_speed3 = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
      new_dx_cooling_coil_speed3.setGrossRatedTotalCoolingCapacity(hash_clg_cap_stgs[3])
      new_dx_cooling_coil_speed3.setGrossRatedSensibleHeatRatio(0.79452681573034)
      new_dx_cooling_coil_speed3.setGrossRatedCoolingCOP(4.44)
      new_dx_cooling_coil_speed3.setRatedAirFlowRate(hash_clg_airflow_stgs[3])
      new_dx_cooling_coil_speed3.setRatedEvaporatorFanPowerPerVolumeFlowRate(773.3)
      new_dx_cooling_coil_speed3.setTotalCoolingCapacityFunctionofTemperatureCurve(cool_cap_ft3)
      new_dx_cooling_coil_speed3.setTotalCoolingCapacityFunctionofFlowFractionCurve(cool_cap_fff_all_stages)
      new_dx_cooling_coil_speed3.setEnergyInputRatioFunctionofTemperatureCurve(cool_eir_ft3)
      new_dx_cooling_coil_speed3.setEnergyInputRatioFunctionofFlowFractionCurve (cool_eir_fff_all_stages)
      new_dx_cooling_coil_speed3.setPartLoadFractionCorrelationCurve(cool_plf_fplr_all_stages)
      new_dx_cooling_coil_speed3.setNominalTimeforCondensateRemovaltoBegin(1000)
      new_dx_cooling_coil_speed3.setRatioofInitialMoistureEvaporationRateandSteadyStateLatentCapacity(1.5)
      new_dx_cooling_coil_speed3.setLatentCapacityTimeConstant(45)
      new_dx_cooling_coil_speed3.setEvaporativeCondenserEffectiveness(0.9)
      new_dx_cooling_coil_speed3.autosizedEvaporativeCondenserAirFlowRate
      new_dx_cooling_coil_speed3.autosizedRatedEvaporativeCondenserPumpPowerConsumption
      new_dx_cooling_coil.addStage(new_dx_cooling_coil_speed3) unless ((hash_clg_speed_level_status[3] == false) || (hash_htg_speed_level_status[3] == false))
      # create stage 4
      new_dx_cooling_coil_speed4 = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
      new_dx_cooling_coil_speed4.setGrossRatedTotalCoolingCapacity(hash_clg_cap_stgs[4])
      new_dx_cooling_coil_speed4.setGrossRatedSensibleHeatRatio(0.784532541812955)
      new_dx_cooling_coil_speed4.setGrossRatedCoolingCOP(4.11)
      new_dx_cooling_coil_speed4.setRatedAirFlowRate(hash_clg_airflow_stgs[4])
      new_dx_cooling_coil_speed4.setRatedEvaporatorFanPowerPerVolumeFlowRate(773.3)
      new_dx_cooling_coil_speed4.setTotalCoolingCapacityFunctionofTemperatureCurve(cool_cap_ft4)
      new_dx_cooling_coil_speed4.setTotalCoolingCapacityFunctionofFlowFractionCurve(cool_cap_fff_all_stages)
      new_dx_cooling_coil_speed4.setEnergyInputRatioFunctionofTemperatureCurve(cool_eir_ft4)
      new_dx_cooling_coil_speed4.setEnergyInputRatioFunctionofFlowFractionCurve (cool_eir_fff_all_stages)
      new_dx_cooling_coil_speed4.setPartLoadFractionCorrelationCurve(cool_plf_fplr_all_stages)
      new_dx_cooling_coil_speed4.setNominalTimeforCondensateRemovaltoBegin(1000)
      new_dx_cooling_coil_speed4.setRatioofInitialMoistureEvaporationRateandSteadyStateLatentCapacity(1.5)
      new_dx_cooling_coil_speed4.setLatentCapacityTimeConstant(45)
      new_dx_cooling_coil_speed4.setEvaporativeCondenserEffectiveness(0.9)
      new_dx_cooling_coil_speed4.autosizedEvaporativeCondenserAirFlowRate
      new_dx_cooling_coil_speed4.autosizedRatedEvaporativeCondenserPumpPowerConsumption
      new_dx_cooling_coil.addStage(new_dx_cooling_coil_speed4) 
      ####################################### End Cooling Performance Curves

      ################################### Heating Performance Curves
      # define performance curves

      # Defrost Energy Input Ratio Function of Temperature Curve
      defrost_eir = OpenStudio::Model::CurveBiquadratic.new(model)
      defrost_eir.setName("#{air_loop_hvac.name} defrost_eir")
      defrost_eir.setCoefficient1Constant(0.1528)
      defrost_eir.setCoefficient2x(0)
      defrost_eir.setCoefficient3xPOW2(0)
      defrost_eir.setCoefficient4y(0)
      defrost_eir.setCoefficient5yPOW2(0)
      defrost_eir.setCoefficient6xTIMESY(0)
      defrost_eir.setMinimumValueofx(-100)
      defrost_eir.setMaximumValueofx(100)
      defrost_eir.setMinimumValueofy(-100)
      defrost_eir.setMaximumValueofy(100)

      # Heating Capacity Function of Temperature Curve - 1
      heat_cap_ft1 = OpenStudio::Model::CurveBiquadratic.new(model)
      heat_cap_ft1.setName("#{air_loop_hvac.name} heat_cap_ft1")
      heat_cap_ft1.setCoefficient1Constant(0.893321031576)
      heat_cap_ft1.setCoefficient2x(-0.00973374264)
      heat_cap_ft1.setCoefficient3xPOW2(6.3643968e-05)
      heat_cap_ft1.setCoefficient4y(0.0391130520048)
      heat_cap_ft1.setCoefficient5yPOW2(-2.50816824e-06)
      heat_cap_ft1.setCoefficient6xTIMESY(-0.000272588652)
      heat_cap_ft1.setMinimumValueofx(-100)
      heat_cap_ft1.setMaximumValueofx(100)
      heat_cap_ft1.setMinimumValueofy(-100)
      heat_cap_ft1.setMaximumValueofy(100)
      # Heating Capacity Function of Temperature Curve - 2
      heat_cap_ft2 = OpenStudio::Model::CurveBiquadratic.new(model)
      heat_cap_ft2.setName("#{air_loop_hvac.name} heat_cap_ft2")
      heat_cap_ft2.setCoefficient1Constant(0.9237345336,)
      heat_cap_ft2.setCoefficient2x(-0.00597077568)
      heat_cap_ft2.setCoefficient3xPOW2(0)
      heat_cap_ft2.setCoefficient4y(0.02781672876)
      heat_cap_ft2.setCoefficient5yPOW2(6.5916828e-05)
      heat_cap_ft2.setCoefficient6xTIMESY(-0.000189254232)
      heat_cap_ft2.setMinimumValueofx(-100)
      heat_cap_ft2.setMaximumValueofx(100)
      heat_cap_ft2.setMinimumValueofy(-100)
      heat_cap_ft2.setMaximumValueofy(100)
      # Heating Capacity Function of Temperature Curve - 3
      heat_cap_ft3 = OpenStudio::Model::CurveBiquadratic.new(model)
      heat_cap_ft3.setName("#{air_loop_hvac.name} heat_cap_ft3")
      heat_cap_ft3.setCoefficient1Constant(0.9620542196)
      heat_cap_ft3.setCoefficient2x(-0.00949277772)
      heat_cap_ft3.setCoefficient3xPOW2(0.000109212948)
      heat_cap_ft3.setCoefficient4y(0.0247078314)
      heat_cap_ft3.setCoefficient5yPOW2(3.4225092e-05)
      heat_cap_ft3.setCoefficient6xTIMESY(-0.000125697744)
      heat_cap_ft3.setMinimumValueofx(-100)
      heat_cap_ft3.setMaximumValueofx(100)
      heat_cap_ft3.setMinimumValueofy(-100)
      heat_cap_ft3.setMaximumValueofy(100)
      # Heating Capacity Function of Temperature Curve - 4
      heat_cap_ft4 = OpenStudio::Model::CurveBiquadratic.new(model)
      heat_cap_ft4.setName("#{air_loop_hvac.name} heat_cap_ft4")
      heat_cap_ft4.setCoefficient1Constant(0.93607915412)
      heat_cap_ft4.setCoefficient2x(-0.005481563544)
      heat_cap_ft4.setCoefficient3xPOW2(-8.5897908e-06)
      heat_cap_ft4.setCoefficient4y(0.02491053192)
      heat_cap_ft4.setCoefficient5yPOW2(5.3087076e-05)
      heat_cap_ft4.setCoefficient6xTIMESY(-0.000155750364)
      heat_cap_ft4.setMinimumValueofx(-100)
      heat_cap_ft4.setMaximumValueofx(100)
      heat_cap_ft4.setMinimumValueofy(-100)
      heat_cap_ft4.setMaximumValueofy(100)

      # Heating Capacity Function of Flow Fraction Curve
      heat_cap_fff_all_stages = OpenStudio::Model::CurveQuadratic.new(model)
      heat_cap_fff_all_stages.setName("#{air_loop_hvac.name} heat_cap_fff_all_stages")
      heat_cap_fff_all_stages.setCoefficient1Constant(1)
      heat_cap_fff_all_stages.setCoefficient2x(0)
      heat_cap_fff_all_stages.setCoefficient3xPOW2(0)
      heat_cap_fff_all_stages.setMinimumValueofx(0)
      heat_cap_fff_all_stages.setMaximumValueofx(2)
      heat_cap_fff_all_stages.setMinimumCurveOutput(0)
      heat_cap_fff_all_stages.setMaximumCurveOutput(2)

      # Energy Input Ratio Function of Temperature Curve - 1
      heat_eir_ft1 = OpenStudio::Model::CurveBiquadratic.new(model)
      heat_eir_ft1.setName("#{air_loop_hvac.name} heat_eir_ft1")
      heat_eir_ft1.setCoefficient1Constant(0.466648487)
      heat_eir_ft1.setCoefficient2x(0.020263329)
      heat_eir_ft1.setCoefficient3xPOW2(0.00126839196)
      heat_eir_ft1.setCoefficient4y(-0.0170161326)
      heat_eir_ft1.setCoefficient5yPOW2(0.00317499588)
      heat_eir_ft1.setCoefficient6xTIMESY(-0.00349609608)
      heat_eir_ft1.setMinimumValueofx(-100)
      heat_eir_ft1.setMaximumValueofx(100)
      heat_eir_ft1.setMinimumValueofy(-100)
      heat_eir_ft1.setMaximumValueofy(100)
      # Energy Input Ratio Function of Temperature Curve - 2
      heat_eir_ft2 = OpenStudio::Model::CurveBiquadratic.new(model)
      heat_eir_ft2.setName("#{air_loop_hvac.name} heat_eir_ft2")
      heat_eir_ft2.setCoefficient1Constant(0.450656859)
      heat_eir_ft2.setCoefficient2x(0.0292902642)
      heat_eir_ft2.setCoefficient3xPOW2(0.00039314484)
      heat_eir_ft2.setCoefficient4y(-0.0097895178)
      heat_eir_ft2.setCoefficient5yPOW2(0.00053936928)
      heat_eir_ft2.setCoefficient6xTIMESY(-0.0011808828)
      heat_eir_ft2.setMinimumValueofx(-100)
      heat_eir_ft2.setMaximumValueofx(100)
      heat_eir_ft2.setMinimumValueofy(-100)
      heat_eir_ft2.setMaximumValueofy(100)
      # Energy Input Ratio Function of Temperature Curve - 3
      heat_eir_ft3 = OpenStudio::Model::CurveBiquadratic.new(model)
      heat_eir_ft3.setName("#{air_loop_hvac.name} heat_eir_ft3")
      heat_eir_ft3.setCoefficient1Constant(0.5725180114)
      heat_eir_ft3.setCoefficient2x(0.02289624912)
      heat_eir_ft3.setCoefficient3xPOW2(0.000266018904)
      heat_eir_ft3.setCoefficient4y(-0.0106675434)
      heat_eir_ft3.setCoefficient5yPOW2(0.00049092156)
      heat_eir_ft3.setCoefficient6xTIMESY(-0.00068136876)
      heat_eir_ft3.setMinimumValueofx(-100)
      heat_eir_ft3.setMaximumValueofx(100)
      heat_eir_ft3.setMinimumValueofy(-100)
      heat_eir_ft3.setMaximumValueofy(100)
      # Energy Input Ratio Function of Temperature Curve - 4
      heat_eir_ft4 = OpenStudio::Model::CurveBiquadratic.new(model)
      heat_eir_ft4.setName("#{air_loop_hvac.name} heat_eir_ft4")
      heat_eir_ft4.setCoefficient1Constant(0.668195855)
      heat_eir_ft4.setCoefficient2x(0.0146719548)
      heat_eir_ft4.setCoefficient3xPOW2(0.00044596332)
      heat_eir_ft4.setCoefficient4y(-0.0114392286)
      heat_eir_ft4.setCoefficient5yPOW2(0.00049710348)
      heat_eir_ft4.setCoefficient6xTIMESY(-0.00069095592)
      heat_eir_ft4.setMinimumValueofx(-100)
      heat_eir_ft4.setMaximumValueofx(100)
      heat_eir_ft4.setMinimumValueofy(-100)
      heat_eir_ft4.setMaximumValueofy(100)

      # Energy Input Ratio Function of Flow Fraction Curve
      heat_eir_fff_all_stages = OpenStudio::Model::CurveQuadratic.new(model)
      heat_eir_fff_all_stages.setName("#{air_loop_hvac.name} heat_eir_fff")
      heat_eir_fff_all_stages.setCoefficient1Constant(1)
      heat_eir_fff_all_stages.setCoefficient2x(0)
      heat_eir_fff_all_stages.setCoefficient3xPOW2(0)
      heat_eir_fff_all_stages.setMinimumValueofx(0)
      heat_eir_fff_all_stages.setMaximumValueofx(2)
      heat_eir_fff_all_stages.setMinimumCurveOutput(0)
      heat_eir_fff_all_stages.setMaximumCurveOutput(2)

      # Part Load Fraction Correlation Curve
      heat_plf_fplr_all_stages = OpenStudio::Model::CurveQuadratic.new(model)
      heat_plf_fplr_all_stages.setName("#{air_loop_hvac.name} heat_plf_fplr")
      heat_plf_fplr_all_stages.setCoefficient1Constant(0.76)
      heat_plf_fplr_all_stages.setCoefficient2x(0.24)
      heat_plf_fplr_all_stages.setCoefficient3xPOW2(0)
      heat_plf_fplr_all_stages.setMinimumValueofx(0)
      heat_plf_fplr_all_stages.setMaximumValueofx(1)
      heat_plf_fplr_all_stages.setMinimumCurveOutput(0.7)
      heat_plf_fplr_all_stages.setMaximumCurveOutput(1)

      # add new multispeed heating coil
      new_dx_heating_coil = OpenStudio::Model::CoilHeatingDXMultiSpeed.new(model)
      new_dx_heating_coil.setName("#{air_loop_hvac.name} Heat Pump Coil")
      new_dx_heating_coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(-17.7778)
      new_dx_heating_coil.setAvailabilitySchedule(always_on)
      new_dx_heating_coil.setDefrostEnergyInputRatioFunctionofTemperatureCurve(defrost_eir) #defrost_eir
      new_dx_heating_coil.setMaximumOutdoorDryBulbTemperatureforDefrostOperation(4.444)
      new_dx_heating_coil.setDefrostStrategy('ReverseCycle')
      new_dx_heating_coil.setDefrostControl('OnDemand')
      new_dx_heating_coil.setDefrostTimePeriodFraction(0.058333)
      new_dx_heating_coil.setApplyPartLoadFractiontoSpeedsGreaterthan1(false)
      new_dx_heating_coil.setFuelType('Electricity')
      new_dx_heating_coil.setRegionnumberforCalculatingHSPF(4)

      # add stage data
      # create stage 1
      new_dx_heating_coil_speed1 = OpenStudio::Model::CoilHeatingDXMultiSpeedStageData.new(model)
      new_dx_heating_coil_speed1.setGrossRatedHeatingCapacity(hash_htg_cap_stgs[1])
      new_dx_heating_coil_speed1.setGrossRatedHeatingCOP(4.96)
      new_dx_heating_coil_speed1.setRatedAirFlowRate(hash_htg_airflow_stgs[1])
      new_dx_heating_coil_speed1.setRatedSupplyAirFanPowerPerVolumeFlowRate(773.3)
      new_dx_heating_coil_speed1.setHeatingCapacityFunctionofTemperatureCurve(heat_cap_ft1)
      new_dx_heating_coil_speed1.setHeatingCapacityFunctionofFlowFractionCurve(heat_cap_fff_all_stages)
      new_dx_heating_coil_speed1.setEnergyInputRatioFunctionofTemperatureCurve(heat_eir_ft1)
      new_dx_heating_coil_speed1.setEnergyInputRatioFunctionofFlowFractionCurve (heat_eir_fff_all_stages)
      new_dx_heating_coil_speed1.setPartLoadFractionCorrelationCurve(heat_plf_fplr_all_stages)
      new_dx_heating_coil.addStage(new_dx_heating_coil_speed1) unless ((hash_clg_speed_level_status[1] == false) || (hash_htg_speed_level_status[1] == false))
      # create stage 2
      new_dx_heating_coil_speed2 = OpenStudio::Model::CoilHeatingDXMultiSpeedStageData.new(model)
      new_dx_heating_coil_speed2.setGrossRatedHeatingCapacity(hash_htg_cap_stgs[2])
      new_dx_heating_coil_speed2.setGrossRatedHeatingCOP(4.24)
      new_dx_heating_coil_speed2.setRatedAirFlowRate(hash_htg_airflow_stgs[2])
      new_dx_heating_coil_speed2.setRatedSupplyAirFanPowerPerVolumeFlowRate(773.3)
      new_dx_heating_coil_speed2.setHeatingCapacityFunctionofTemperatureCurve(heat_cap_ft2)
      new_dx_heating_coil_speed2.setHeatingCapacityFunctionofFlowFractionCurve(heat_cap_fff_all_stages)
      new_dx_heating_coil_speed2.setEnergyInputRatioFunctionofTemperatureCurve(heat_eir_ft2)
      new_dx_heating_coil_speed2.setEnergyInputRatioFunctionofFlowFractionCurve (heat_eir_fff_all_stages)
      new_dx_heating_coil_speed2.setPartLoadFractionCorrelationCurve(heat_plf_fplr_all_stages)
      new_dx_heating_coil.addStage(new_dx_heating_coil_speed2) unless ((hash_clg_speed_level_status[2] == false) || (hash_htg_speed_level_status[2] == false))
      # create stage 3
      new_dx_heating_coil_speed3 = OpenStudio::Model::CoilHeatingDXMultiSpeedStageData.new(model)
      new_dx_heating_coil_speed3.setGrossRatedHeatingCapacity(hash_htg_cap_stgs[3])
      new_dx_heating_coil_speed3.setGrossRatedHeatingCOP(3.59)
      new_dx_heating_coil_speed3.setRatedAirFlowRate(hash_htg_airflow_stgs[3])
      new_dx_heating_coil_speed3.setRatedSupplyAirFanPowerPerVolumeFlowRate(773.3)
      new_dx_heating_coil_speed3.setHeatingCapacityFunctionofTemperatureCurve(heat_cap_ft3)
      new_dx_heating_coil_speed3.setHeatingCapacityFunctionofFlowFractionCurve(heat_cap_fff_all_stages)
      new_dx_heating_coil_speed3.setEnergyInputRatioFunctionofTemperatureCurve(heat_eir_ft3)
      new_dx_heating_coil_speed3.setEnergyInputRatioFunctionofFlowFractionCurve (heat_eir_fff_all_stages)
      new_dx_heating_coil_speed3.setPartLoadFractionCorrelationCurve(heat_plf_fplr_all_stages)
      new_dx_heating_coil.addStage(new_dx_heating_coil_speed3) unless ((hash_clg_speed_level_status[3] == false) || (hash_htg_speed_level_status[3] == false))
      # create stage 4
      new_dx_heating_coil_speed4 = OpenStudio::Model::CoilHeatingDXMultiSpeedStageData.new(model)
      new_dx_heating_coil_speed4.setGrossRatedHeatingCapacity(hash_htg_cap_stgs[4])
      new_dx_heating_coil_speed4.setGrossRatedHeatingCOP(3.42)
      new_dx_heating_coil_speed4.setRatedAirFlowRate(hash_htg_airflow_stgs[4])
      new_dx_heating_coil_speed4.setRatedSupplyAirFanPowerPerVolumeFlowRate(773.3)
      new_dx_heating_coil_speed4.setHeatingCapacityFunctionofTemperatureCurve(heat_cap_ft4)
      new_dx_heating_coil_speed4.setHeatingCapacityFunctionofFlowFractionCurve(heat_cap_fff_all_stages)
      new_dx_heating_coil_speed4.setEnergyInputRatioFunctionofTemperatureCurve(heat_eir_ft4)
      new_dx_heating_coil_speed4.setEnergyInputRatioFunctionofFlowFractionCurve (heat_eir_fff_all_stages)
      new_dx_heating_coil_speed4.setPartLoadFractionCorrelationCurve(heat_plf_fplr_all_stages)
      new_dx_heating_coil.addStage(new_dx_heating_coil_speed4)
      ####################################### End Heating Performance Curves

      # add new supplemental heating coil
      new_backup_heating_coil = nil
      # define backup heat source TODO: set capacity to equal full heating capacity
      if (prim_ht_fuel_type == 'electric') || (backup_ht_fuel_scheme=='electric_resistance_backup')
        new_backup_heating_coil = OpenStudio::Model::CoilHeatingElectric.new(model)
        new_backup_heating_coil.setEfficiency(1.0)
        new_backup_heating_coil.setName("#{air_loop_hvac.name} electric resistance backup coil")
      else
        new_backup_heating_coil = OpenStudio::Model::CoilHeatingGas.new(model)
        new_backup_heating_coil.setGasBurnerEfficiency(0.80)
        new_backup_heating_coil.setName("#{air_loop_hvac.name} gas backup coil")
      end
      # set availability schedule
      new_backup_heating_coil.setAvailabilitySchedule(always_on)
      # set capacity of backup heat to meet full heating load
      new_backup_heating_coil.setNominalCapacity(orig_htg_coil_gross_cap)

      # add new fan
      new_fan = OpenStudio::Model::FanVariableVolume.new(model, always_on)
      new_fan.setAvailabilitySchedule(supply_fan_avail_sched)
      new_fan.setName("#{air_loop_hvac.name} VFD Fan")
      new_fan.setFanTotalEfficiency(0.63) # from PNNL
      new_fan.setMotorEfficiency(fan_mot_eff) # from Daikin Rebel E+ file
      new_fan.setFanPowerCoefficient1(0.242469) # from Daikin Rebel E+ file
      new_fan.setFanPowerCoefficient2(-1.46455) # from Daikin Rebel E+ file
      new_fan.setFanPowerCoefficient3(4.496391) # from Daikin Rebel E+ file
      new_fan.setFanPowerCoefficient4(-3.6426) # from Daikin Rebel E+ file
      new_fan.setFanPowerCoefficient5(1.301203) # from Daikin Rebel E+ file
      new_fan.setFanPowerMinimumFlowRateInputMethod("Fraction")

      # set minimum fan power flow fraction to the higher of 0.40 or the min flow fraction
      if min_airflow_ratio > min_flow
        new_fan.setFanPowerMinimumFlowFraction(min_airflow_ratio)
      else
        new_fan.setFanPowerMinimumFlowFraction(min_flow)
      end
      new_fan.setPressureRise(fan_static_pressure) # set from origial fan power; 0.5in will be added later if adding HR

      # add new unitary system object
      new_air_to_air_heatpump =  OpenStudio::Model::AirLoopHVACUnitarySystem.new(model)
      new_air_to_air_heatpump.setName("#{air_loop_hvac.name} Unitary Heat Pump System")
      new_air_to_air_heatpump.setSupplyFan(new_fan)
      new_air_to_air_heatpump.setHeatingCoil(new_dx_heating_coil)
      new_air_to_air_heatpump.setCoolingCoil(new_dx_cooling_coil) 
      new_air_to_air_heatpump.setSupplementalHeatingCoil(new_backup_heating_coil)
      new_air_to_air_heatpump.addToNode(air_loop_hvac.supplyOutletNode()) 

      # set other features
      new_air_to_air_heatpump.setControllingZoneorThermostatLocation(control_zone)
      new_air_to_air_heatpump.setFanPlacement('DrawThrough')
      new_air_to_air_heatpump.setAvailabilitySchedule(unitary_availability_sched)
      new_air_to_air_heatpump.setDehumidificationControlType(dehumid_type)
      new_air_to_air_heatpump.setSupplyAirFanOperatingModeSchedule(supply_fan_op_sched)
      new_air_to_air_heatpump.setControlType('Load') ##cc-tmp
      new_air_to_air_heatpump.setName("#{thermal_zone.name} RTU SZ-VAV Heat Pump")
      new_air_to_air_heatpump.setMaximumSupplyAirTemperature(50) 
      new_air_to_air_heatpump.setDXHeatingCoilSizingRatio(1+performance_oversizing_factor)
      # set cooling design flow rate
      new_air_to_air_heatpump.setSupplyAirFlowRateMethodDuringCoolingOperation('SupplyAirFlowRate')
      new_air_to_air_heatpump.setSupplyAirFlowRateDuringCoolingOperation(hash_htg_airflow_stgs[4])
      # set heating design flow rate
      new_air_to_air_heatpump.setSupplyAirFlowRateMethodDuringHeatingOperation('SupplyAirFlowRate')
      new_air_to_air_heatpump.setSupplyAirFlowRateDuringHeatingOperation(hash_clg_airflow_stgs[4])
      # set no load design flow rate
      new_air_to_air_heatpump.setSupplyAirFlowRateMethodWhenNoCoolingorHeatingisRequired('SupplyAirFlowRate')
      new_air_to_air_heatpump.setSupplyAirFlowRateWhenNoCoolingorHeatingisRequired(min_airflow_m3_per_s)

      # new_air_to_air_heatpump.setDOASDXCoolingCoilLeavingMinimumAirTemperature(7.5) # set minimum discharge temp to 45F, required for VAV operation

      # add dcv to air loop if dcv flag is true
      if dcv==true
        oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
        controller_oa = oa_system.getControllerOutdoorAir
        controller_mv = controller_oa.controllerMechanicalVentilation
        controller_mv.setDemandControlledVentilation(true)
      end

      # add economizer
      if econ==true
        # set parameters
        oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
        controller_oa = oa_system.getControllerOutdoorAir
        # econ_type = std.model_economizer_type(model, climate_zone)
        # set economizer type
        controller_oa.setEconomizerControlType('DifferentialEnthalpy')
        # set drybulb temperature limit; per 90.1-2013, this is constant 75F for all climates
        drybulb_limit_f=75
        drybulb_limit_c = OpenStudio.convert(drybulb_limit_f, 'F', 'C').get
        controller_oa.setEconomizerMaximumLimitDryBulbTemperature(drybulb_limit_c)
        # set lockout for integrated heating
        controller_oa.setLockoutType('LockoutWithHeating')
      end

      # make sure existing economizer is integrated or it wont work with multispeed coil
      oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
      controller_oa = oa_system.getControllerOutdoorAir
      controller_oa.setLockoutType('LockoutWithHeating') unless controller_oa.getEconomizerControlType == "NoEconomizer"


      # Energy recovery
      # check for ERV, and get components
      # ERV components will be removed and replaced if ERV flag was selected
      # If ERV flag was not selected, ERV equipment will remain in place as-is
      erv_components = []
        air_loop_hvac.oaComponents.each do |component|
            component_name = component.name.to_s
            next if component_name.include? "Node"
            if component_name.include? "ERV"
              erv_components << component
              erv_components = erv_components.uniq
            end
          end  
      
      # add energy recovery if specified
      if hr==true
        # if there was not previosuly an ERV, add 0.5" (124.42 pascals) static to supply fan
        new_fan.setPressureRise(fan_static_pressure + 124.42) if erv_components.empty?
        # remove existing ERV; these will be replaced with new ERV equipment
        erv_components.each(&:remove)
        # get oa system
        oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
        # add new HR system
        new_hr = OpenStudio::Model::HeatExchangerAirToAirSensibleAndLatent.new(model)
        # update parameters
        new_hr.addToNode(oa_system.outboardOANode.get)
        new_hr.setAvailabilitySchedule(always_on)
        new_hr.setEconomizerLockout(true)
        new_hr.setFrostControlType('ExhaustOnly')
        new_hr.setThresholdTemperature(0) # 32F, from Daikin
        new_hr.setInitialDefrostTimeFraction(0.083) # 5 minutes every 60 minutes, from Daikin
        new_hr.setRateofDefrostTimeFractionIncrease(0.024) # from E+ recommended values
        new_hr.setHeatExchangerType('Rotary')
        new_hr.setName("#{air_loop_hvac.name} ERV")
        # set wheel power consumption; from DOE prototypes which exceed 90.1
        default_fan_efficiency = 0.5
        power = (oa_flow_m3_per_s * 212.5 / default_fan_efficiency) + (oa_flow_m3_per_s * 0.9 * 162.5 / default_fan_efficiency) + 50
        new_hr.setNominalElectricPower(power)
        # set efficiencies; from DOE prototypes which exceed 90.1
        new_hr.setSupplyAirOutletTemperatureControl(false)
        new_hr.setSensibleEffectivenessat100HeatingAirFlow(0.76)
        new_hr.setSensibleEffectivenessat75HeatingAirFlow(0.81)
        new_hr.setLatentEffectivenessat100HeatingAirFlow(0.68)
        new_hr.setLatentEffectivenessat75HeatingAirFlow(0.73)
        new_hr.setSensibleEffectivenessat100CoolingAirFlow(0.76)
        new_hr.setSensibleEffectivenessat75CoolingAirFlow(0.81)
        new_hr.setLatentEffectivenessat100CoolingAirFlow(0.68)
        new_hr.setLatentEffectivenessat75CoolingAirFlow(0.73)
      end
    end
        
    # report final condition of model
    # runner.registerFinalCondition("The building finished with heat pump RTUs replacing the HVAC equipment for #{selected_air_loops.size} air loops. Cumulatively, the installed RTUs have been upsized by a factor of #{(cum_applied_cool_cap / cum_req_cool_cap).round(2)} to accomodate additional heating capacity, which results in #{OpenStudio.convert(cum_applied_cool_cap, 'W', 'ton').get.round(2)} tons of cooling, #{OpenStudio.convert(cum_applied_htg_cap_at_rated_47f, 'W', 'ton').get.round(2)} tons of heating at rated conditions (47F), and #{OpenStudio.convert(cum_req_htg_cap, 'W', 'ton').get.round(2)} tons of #{backup_heat_source} backup heating. For reference, the cumulative heat pump capacity is capable of supplying #{((cum_applied_htg_cap_at_rated_47f / cum_req_htg_cap)*100).round(2)}% of the design heating load at 47F, #{((cum_applied_htg_cap_at_17f / cum_req_htg_cap)*100).round(2)}% at 17F, #{((cum_applied_htg_cap_at_0f / cum_req_htg_cap)*100).round(2)}% at 0F, and no capacity below 0F due to the cutoff temperature, while the weather file heating design day temperature is #{OpenStudio.convert(wntr_design_day_temp_c, 'C', 'F').get.round(0)}F.")

    return true
  end
end

# register the measure to be used by the application
AddHeatPumpRtu.new.registerWithApplication
