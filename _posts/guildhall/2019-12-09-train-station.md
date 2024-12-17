---
layout: post
title: Train Station - Left4Dead
description: >-
  The level "Train Station" belongs to the campaign "Finalstop", and is served as the first level. The whole campaign includes 4 levels, respectively they are Train Station, Sewer, Swamp, and Prison, here the blog is mainly focused on level 1 -- "Train Station".
date: 2019-12-10 06:49 +0800
categories: [Archived Projects, Guildhall]
tags: [Archived]
media_subpath: /assets/img/post-data/guildhall/train-station/
---

{% include obsolete_warning.html %}

## Screenshots
![Screenshot](train_station_1.webp)
_Screenshot_

![Screenshot](train_station_2.webp)
_Screenshot_

![Screenshot](train_station_3.webp)
_Screenshot_

![Screenshot](train_station_4.webp)
_Screenshot_

![Screenshot](train_station_5.webp)
_Screenshot_

![Screenshot](train_station_6.webp)
_Screenshot_

![Screenshot](train_station_7.webp)
_Screenshot_

## Level Layout
![Level Layout](train_station_8.webp)
_Level Layout_

![Level Layout](train_station_9.webp)
_Level Layout_

![Level Layout](train_station_10.webp)
_Level Layout_

![Level Layout](train_station_11.webp)
_Level Layout_

![Level Layout](train_station_12.webp)
_Level Layout_

## Post Mortem
### What went well
- Pre-plan and flexible working attitude
  - During the planning phase, we had multiple conversations on what the story, transitions, geolocation of each level was going to be. Fortunately, we underwent a quite smooth experience involving rapid change and iteration on these plans.

- Do not design on the fly
  - It’s very important to have a quick block-out campaign in the early stage before deciding on the final campaign proposal so that everyone can have a clear idea of how the gameplay would look like in the future. Also, that also exposes the core technology issue and other risks.

- Source-Control and File Convention
  - For a whole campaign that involves multiple designers, multiple levels, it is almost vital to have a clear file convention and reliable source-control method. Source-Control can also provide stable build when submission, instead of manually gathering every file before the deadline.

- Automated Process
  - In the early stage of development, we realized that letting only 1 person be responsible for packaging all teammates' files is a waterfall process because he/she needs to wait until the final submission has been made, and do a bunch of repetitive processes in order to make a build. To solve that, we created a python automation script that can automatically pull the latest file from source-control and do a one-click package, so that everyone can easily make packages without causing mistakes.

### What went wrong
- Team-wide Communication
  - In this project, each level needs to be connected seamlessly with other levels, which usually involves 2 to 3 designers to discuss about each transition, however, as a 4 designers’ team, we, unfortunately, lacking team-wide communication, for instance, level 1 designer had very few conversations with level 3 and level 4 designers, vice versa. This issue leads to a lot of other issues in the future. 

- Time Management
  - Time management in this project is not very good. We usually do a very hurry test right before the deadline without having time to refine or change anything we found in the playthrough. So, every milestone we are behind the expected deliverable.

- Unable to Hit Stable Milestone Submission
  - Because of the time management issue, we are not able to hit stable milestone submissions, it usually has flaws here and there, with transition inconsistent or not fully working. Which is very unacceptable.

- Lack of production management/leads
  - Build upon that, the issue was also caused by a lack of production management, or leaders, because all designers are working under parallel RACI, so no one could really influence other’s work. 

### What I learned

- Think like a project manager
  - Even as a designer, I think it is very important to think like a project manager, other than just do what we are planned to do, because a team project is evaluated as a whole, rather than personal performance.

- Team-wide Communication
  - It’s necessary to have an idea of where the whole project is at, so team-wide communication would help with this, and eliminate possible risks that will be brought up in the future.

- Stability overweight others before the deadline
  - Before the deadline, every change should raise caution, and the quantity of playtests should be leveraged up, simply because we’d rather have a stable but slightly lower quality build than an awesome looking but crash/does not work build.

- Automation is a good touch
  - For repetitive work that does not quite need manual interferes, spent a bit time to let them automated is a good approach, which can lower the chance of making mistakes, as well as save a bunch of time doing these works. Which saves more time for other actual development works.

## Things to carry on in the future
### Systematic Thoughts
- Before jump into works, having a systematic thought is a good approach, has a good knowledge of the engine/editor, some pre-projects to evaluate some key features as well as risks. Working with plans and milestones, etc. These all help the development phase go smoothly.
### Detailed Pre-Plan
- Before deciding the project proposal, a couple of detailed level paper maps/Whitebox would help prove if technological-wise the project is viable. It would also help address some potential risks and inconsistencies.
### NavMesh needs to be finalized before the aesthetic pass
- Using static meshes is indeed faster than manually block out the whole level, but then it will screw up the navmesh because of the collision meshes have internally. Next time, do make sure the level is properly blocked out, to avoid going back and forth on fixing navmeshes

### Vertical Terrain is not a good choice
- Using vertical terrain helps align the joint part, however, it’s not how the terrain looks like in the real world. Next time, using walls to block the terrains patches, and sculpt them to have a steady slope, to better mimic the aesthetic of terrain.

### Performance
- Skybox should be shaped in a way that perfectly covers the scene, without having a large box to make the visibility test to take forever.

- Avoid a large line of sight, as there will be too many BSP clusters being rendered at the same time. Which will eventually lead to a noticeable framerate drop?

## Challenges and Solutions
### Long LoS (Line of Sight)
- Long LoS will result in camera surpasses the LOD range, which leads to a disbelief and immersion breaking for players

### Use LoS blocker to avoid long range LoS
- Changing LOD range (will increase performance cost)

### Rounded Shape in Hammer
- Shapes like arch or holes are very tricky because the vertices are not able to align to grid on their own
- Try to avoid them
- Try to make them with polygon if possible
- Manually adjust each vertex slightly until they aligned to the grid

### Tilling and Plain Texture
- Plain textures with tiling will break the immersion for players
- Overlay can greatly increase the natural look of a scene

### Exterior Terrain Patches
- Terrain patches in hammer will be tricky to polish at the seam of connection, sometimes will even cause incorrect lighting
- Try to hide them behind artificial constructions (walls, etc.)
- Hide the curved connection part with foliage
- Bring in aesthetic assets too early

### NavMesh will be screwed by mesh collision
- Later as more assets being checked in, much more difficult to debug them